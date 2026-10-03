# Stage 2 search experiments (host side).
CC ?= cc
CFLAGS ?= -O2 -std=c99 -Wall -Wno-unused-function
PROGS := $(basename $(wildcard s2_*.c))

.PHONY: all clean

all: $(PROGS)

# Each program #includes common.h, which #includes ../../solver.c.
%: %.c common.h ../../solver.c
	$(CC) $(CFLAGS) $< -o $@

clean:
	$(RM) $(PROGS)
