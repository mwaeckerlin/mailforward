/**

mailforward init: minimal, shell-free entrypoint for the mailforward
container.

Follows the same three-stage / statically-linked / execv() pattern as
the sibling mwaeckerlin/rspamd and mwaeckerlin/clamav inits: parse env,
compose runtime config through postconf, exec the postfix master. The
runtime image contains no shell, no perl, no busybox.

Behaviour (port of the former start.sh, contract unchanged):

  1. MAPPINGS ("src@dom dest@other; src2@dom2 dest2@…") is written to
     /etc/postfix/virtual (one mapping per line) and compiled with
     postmap. The alias domains are derived from the source addresses
     and published as virtual_alias_domains.
  2. DOMAIN = MAILHOST, or the first of LOCAL_DOMAINS + alias domains.
     It becomes myhostname and selects the TLS certificate directory.
  3. GREYLIST=host or host:port (default port 10025): configure the
     greylist milter unless already configured.
  4. TLS is enabled when /etc/letsencrypt/live/$DOMAIN/ holds
     fullchain.pem + privkey.pem.
  5. Delivery-affecting limits from env — high, configurable defaults
     (MESSAGE_SIZE_LIMIT default 100 GiB, SMTP_HARD_ERROR_LIMIT 20;
     the previously hardcoded smtpd_hard_error_limit=1 turned a single
     5xx into an abrupt 421).
  6. postsuper queue sanity, then exec master in init mode (-i) as
     PID 1. maillog_file=/dev/stdout keeps logs on stdout.
  7. Every env value is whitelist-validated before it is rendered into
     the virtual map or fed to postconf — a malformed value (a newline
     above all: config injection) aborts the start with a clear
     `invalid <VAR>` error. Pinned by tests/config-validation.sh.

Supports --healthcheck: TCP-probes the SMTP listener at 127.0.0.1:25
(replaces the former bash/telnet health.sh).

*/

#include <arpa/inet.h>
#include <cctype>
#include <cerrno>
#include <cstdlib>
#include <cstring>
#include <exception>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <netinet/in.h>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <sys/socket.h>
#include <sys/wait.h>
#include <unistd.h>
#include <vector>

namespace fs = std::filesystem;

namespace {

constexpr const char *POSTCONF   = "/usr/sbin/postconf";
constexpr const char *POSTMAP    = "/usr/sbin/postmap";
constexpr const char *POSTSUPER  = "/usr/sbin/postsuper";
constexpr const char *MASTER     = "/usr/libexec/postfix/master";
constexpr const char *VIRTUAL    = "/etc/postfix/virtual";

std::string
env_or(const char *name, const std::string &fallback = {}) {
  const char *v = std::getenv(name);
  return (v && *v) ? std::string(v) : fallback;
}

// Every env value is rendered into the virtual(5) map or fed to
// `postconf -e`, so an unvalidated value — a newline above all —
// would inject arbitrary extra directives (config injection).
// Operator input is input: whitelist-validate each value class and
// refuse to start on anything malformed (pinned by
// tests/config-validation.sh).
[[noreturn]] void
die_invalid(const char *var, const std::string &value) {
  std::cerr << "**** ERROR: invalid " << var << " \"" << value
            << "\" — refusing to start" << std::endl;
  std::exit(1);
}

// Empty stays allowed: every knob is optional — validation constrains
// only what IS set.
void
check_chars(const char *var, const std::string &v, const std::string &extra) {
  for (char c : v)
    if (!std::isalnum(static_cast<unsigned char>(c)) &&
        extra.find(c) == std::string::npos)
      die_invalid(var, v);
}

long
check_num(const char *var, const std::string &v, long min, long max) {
  if (v.empty() || v.size() > 15 ||
      v.find_first_not_of("0123456789") != std::string::npos)
    die_invalid(var, v);
  long n = std::atol(v.c_str());
  if (n < min || n > max) die_invalid(var, v);
  return n;
}

// Capture ONLY stdout — stderr stays on the container log. postconf
// prints deprecation warnings on stderr; mixing them into a captured
// `postconf -h` value would feed multi-line garbage back into
// `postconf -e`.
int
run_capture(const std::vector<const char *> &argv, std::string &out) {
  int pipefd[2];
  if (pipe(pipefd) < 0) throw std::runtime_error("pipe");
  pid_t pid = fork();
  if (pid < 0) throw std::runtime_error("fork");
  if (pid == 0) {
    close(pipefd[0]);
    dup2(pipefd[1], 1);
    close(pipefd[1]);
    std::vector<char *> a;
    for (auto *s : argv) a.push_back(const_cast<char *>(s));
    a.push_back(nullptr);
    execv(a[0], a.data());
    _exit(127);
  }
  close(pipefd[1]);
  char buf[4096];
  ssize_t n;
  while ((n = read(pipefd[0], buf, sizeof buf)) > 0) out.append(buf, n);
  close(pipefd[0]);
  int status = 0;
  waitpid(pid, &status, 0);
  return WIFEXITED(status) ? WEXITSTATUS(status) : -1;
}

void
postconf_set(const std::string &name, const std::string &value) {
  std::string out;
  const std::string assignment = name + "=" + value;
  if (run_capture({POSTCONF, "-e", assignment.c_str()}, out) != 0)
    throw std::runtime_error("postconf -e " + assignment + " failed: " + out);
}

std::string
postconf_get(const std::string &name) {
  std::string out;
  if (run_capture({POSTCONF, "-h", name.c_str()}, out) != 0)
    throw std::runtime_error("postconf -h " + name + " failed: " + out);
  while (!out.empty() && (out.back() == '\n' || out.back() == '\r'))
    out.pop_back();
  return out;
}

std::string
trim(const std::string &s) {
  const auto b = s.find_first_not_of(" \t");
  if (b == std::string::npos) return {};
  const auto e = s.find_last_not_of(" \t");
  return s.substr(b, e - b + 1);
}

std::string
with_default_port(std::string hostport, const std::string &port) {
  if (hostport.find(':') == std::string::npos) hostport += ":" + port;
  return hostport;
}

// MAPPINGS entries are separated by ';'. Each entry becomes one line
// of the virtual(5) map. The alias domains are the domain parts of
// each entry's FIRST (source) address.
struct Mappings {
  std::string virtual_lines;
  std::set<std::string> alias_domains;
};

Mappings
parse_mappings(const std::string &mappings) {
  Mappings m;
  std::istringstream in(mappings);
  std::string entry;
  while (std::getline(in, entry, ';')) {
    entry = trim(entry);
    if (entry.empty()) continue;
    m.virtual_lines += entry + "\n";
    std::istringstream fields(entry);
    std::string source;
    fields >> source;
    const auto at = source.find('@');
    const std::string domain = at == std::string::npos
                             ? source : source.substr(at + 1);
    if (!domain.empty()) m.alias_domains.insert(domain);
  }
  return m;
}

std::string
join(const std::set<std::string> &items) {
  std::string out;
  for (const auto &i : items) {
    if (!out.empty()) out += " ";
    out += i;
  }
  return out;
}

// DISABLE_DNSBL: strip every DNS-blocklist lookup (reject_rbl_client /
// reject_rhsbl_*) from the smtpd restriction lists, keeping the rest
// of each list untouched. For test and offline stacks whose resolver
// cannot answer the blocklist zones — every lookup would stall the
// SMTP dialogue until the resolver timeout.
void
disable_dnsbl() {
  if (env_or("DISABLE_DNSBL").empty()) return;
  for (const char *param : {"smtpd_client_restrictions",
                            "smtpd_helo_restrictions",
                            "smtpd_sender_restrictions",
                            "smtpd_recipient_restrictions",
                            "smtpd_relay_restrictions"}) {
    std::string filtered;
    std::istringstream in(postconf_get(param));
    std::string item;
    while (std::getline(in, item, ',')) {
      item = trim(item);
      if (item.empty() ||
          item.rfind("reject_rbl_client", 0) == 0 ||
          item.rfind("reject_rhsbl_", 0) == 0) continue;
      if (!filtered.empty()) filtered += ", ";
      filtered += item;
    }
    postconf_set(param, filtered);
  }
  std::cerr << "**** DNSBL/RBL checks disabled" << std::endl;
}

void
configure_greylist_milter() {
  std::string greylist = env_or("GREYLIST");
  if (greylist.empty()) return;
  greylist = with_default_port(greylist, "10025");
  const std::string addr = "inet:" + greylist;
  if (postconf_get("smtpd_milters").find(addr) != std::string::npos)
    return;  // already configured
  postconf_set("smtpd_milters",         addr);
  postconf_set("non_smtpd_milters",     addr);
  postconf_set("milter_default_action", "accept");
  postconf_set("milter_protocol",       "6");
  std::cerr << "**** Greylisting milter configured to use "
            << greylist << std::endl;
}

void
configure_tls(const std::string &domain) {
  const std::string live = "/etc/letsencrypt/live/" + domain;
  if (!fs::exists(live + "/fullchain.pem") ||
      !fs::exists(live + "/privkey.pem")) return;
  postconf_set("smtpd_tls_cert_file",      live + "/fullchain.pem");
  postconf_set("smtpd_tls_key_file",       live + "/privkey.pem");
  postconf_set("smtpd_tls_security_level", "may");
  std::cerr << "**** TLS configured for " << domain << std::endl;
}

void
configure_limits() {
  const std::string size = env_or("MESSAGE_SIZE_LIMIT",    "107374182400");
  const std::string herr = env_or("SMTP_HARD_ERROR_LIMIT", "20");
  postconf_set("message_size_limit",     size);
  postconf_set("mailbox_size_limit",     size);
  postconf_set("smtpd_hard_error_limit", herr);
  std::cerr << "**** message_size_limit=" << size
            << ", smtpd_hard_error_limit=" << herr << std::endl;
}

[[noreturn]] void
exec_master() {
  std::string out;
  if (run_capture({POSTSUPER}, out) != 0)
    throw std::runtime_error("postsuper queue sanity failed: " + out);
  if (!out.empty()) std::cerr << out;

  if (getpid() == 1) {
    const char *argv[] = {"master", "-i", nullptr};
    execv(MASTER, const_cast<char *const *>(argv));
  } else {
    const char *argv[] = {"master", "-d", "-s", nullptr};
    execv(MASTER, const_cast<char *const *>(argv));
  }
  std::perror(MASTER);
  std::exit(1);
}

// --------------------------------------------------- healthcheck ----------

int
tcp_probe(const std::string &host, int port) {
  int s = socket(AF_INET, SOCK_STREAM, 0);
  if (s < 0) return 1;
  sockaddr_in addr{};
  addr.sin_family = AF_INET;
  addr.sin_port = htons(port);
  inet_pton(AF_INET, host.c_str(), &addr.sin_addr);
  int rc = connect(s, reinterpret_cast<sockaddr *>(&addr), sizeof addr);
  close(s);
  return rc == 0 ? 0 : 1;
}

} // namespace

int main(int argc, char *argv[]) try {
  // Validate every env value before it is rendered anywhere — also on
  // the --healthcheck path, so a misconfigured container reports
  // unhealthy instead of probing a listener that never came up.
  // MAPPINGS charset: addresses ('@._-+'), entry separator (';') and
  // the source/destination separator (space) — no newline, so the
  // derived alias domains stay safe for postconf.
  check_chars("MAPPINGS",      env_or("MAPPINGS"),      "@._-+; ");
  check_chars("LOCAL_DOMAINS", env_or("LOCAL_DOMAINS"), ".- ");
  check_chars("MAILHOST",      env_or("MAILHOST"),      ".-");
  check_chars("GREYLIST",      env_or("GREYLIST"),      ".-_:");
  check_num("MESSAGE_SIZE_LIMIT",
            env_or("MESSAGE_SIZE_LIMIT", "107374182400"), 0, 999999999999999L);
  check_num("SMTP_HARD_ERROR_LIMIT",
            env_or("SMTP_HARD_ERROR_LIMIT", "20"), 1, 1000000);

  if (argc > 1 && std::string(argv[1]) == "--healthcheck")
    return tcp_probe("127.0.0.1", 25);

  const Mappings m = parse_mappings(env_or("MAPPINGS"));
  const std::string alias_domains = join(m.alias_domains);
  const std::string local_domains = env_or("LOCAL_DOMAINS");

  std::string domain = env_or("MAILHOST");
  if (domain.empty()) {
    std::istringstream all(local_domains + " " + alias_domains);
    all >> domain;
  }

  {
    std::ofstream out(VIRTUAL, std::ios::trunc);
    if (!out) throw std::runtime_error("cannot write /etc/postfix/virtual");
    out << m.virtual_lines;
  }

  disable_dnsbl();
  configure_greylist_milter();
  configure_tls(domain);

  postconf_set("myhostname",            domain);
  postconf_set("mydestination",         local_domains);
  postconf_set("virtual_alias_domains", alias_domains);
  // lmdb, not hash: alpine builds postfix without Berkeley DB, so the
  // historical `hash:` type no longer exists — every alias lookup drew
  // a 451 «Temporary lookup failure». lmdb is alpine's
  // default_database_type; lookup and postmap use the same explicit
  // prefix so map and reader can never diverge.
  postconf_set("virtual_alias_maps",    "lmdb:/etc/postfix/virtual");
  const std::string lmdb_virtual = std::string("lmdb:") + VIRTUAL;
  std::string out;
  if (run_capture({POSTMAP, lmdb_virtual.c_str()}, out) != 0)
    throw std::runtime_error("postmap failed: " + out);

  configure_limits();

  std::cerr << "**** Starting postfix master (mailforward) for "
            << domain << ", forwarding: " << alias_domains << std::endl;
  exec_master();
} catch (const std::exception &e) {
  std::cerr << "EXCEPTION: " << e.what() << std::endl;
  return 1;
} catch (...) {
  std::cerr << "UNKNOWN ERROR" << std::endl;
  return 1;
}
