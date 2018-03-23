#!/bin/bash

echo | telnet 127.0.0.1 25 2> /dev/null | grep -q 'Connected to 127.0.0.1.'
