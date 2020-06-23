## Overview

FPGA firmware for storing and retrieving hits in a track reconstruction environment.

Hits must be stored and retrieved at a rate of one per clock cycle, at rates up to 200 MHz.
Up to 4 hits can be stored for each memory address.
There are 65536 memory addresses.
The memory needs to be cleared in between collision events.

Some documentation available at https://www.dropbox.com/s/y80ykxzthbrcd49/%282016-12-19%29%20FPGA%20and%20Pixel%20Presentation%20for%20Ben.pdf?dl=0.

## NOTE

This package is outdated. There are changes to the HXMPP structure (including bug fixes) in the version which is in the collaborative EXTF codebase.
