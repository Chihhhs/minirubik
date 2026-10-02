# Stage 1 exploration programs (host side) and Ripes measurements.
CC ?= cc
CFLAGS ?= -O2 -std=c99 -Wall -Wno-unused-function
PROGS := ex1 ex2 ex3 ex4 ex5 ex6

.PHONY: all clean mem ips

all: $(PROGS)

# Each program #includes ../../solver.c, so rebuild when it changes.
%: %.c ../../solver.c
	$(CC) $(CFLAGS) $< -o $@

# Ex7: host bytes per guest byte on Ripes (needs RIPES, see the script).
mem:
	./measure_mem.sh

# Ex8: retired instructions per second on Ripes.
ips:
	./measure_ips.sh

clean:
	$(RM) $(PROGS)
