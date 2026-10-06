# Stage 3: host programs (s3_*.c) and RV32I builds (rv_*.c -> rv_*.elf).
#   make s3_check && ./s3_check      tables.h == host tables, H1, H2
#   make s3_ida && ./s3_ida          node counts + H3 for ida.h
#   make s3_ida LOW=1 && ./s3_ida    same for ida_low.h
#   make rv_ida.elf && ./run.sh rv_ida.elf [RV32_5S]   Ripes retired count
CC ?= cc
CFLAGS ?= -O2 -std=c99 -Wall -Wno-unused-function
RVCC := riscv64-elf-gcc
RVFLAGS := -O2 -march=rv32i -mabi=ilp32 -std=c99 -Wall \
           -nostdlib -ffreestanding -Wl,-e,_start
HOST := $(basename $(wildcard s3_*.c))
RV := $(patsubst %.c,%.elf,$(wildcard rv_*.c))

.PHONY: all clean FORCE

all: $(HOST) tables.h tables.s $(RV)

# Host programs may #include "../stage2/common.h" (-> ../../solver.c).
%: %.c $(filter-out tables.h,$(wildcard *.h)) ../stage2/common.h ../../solver.c
	$(CC) $(CFLAGS) $< -o $@

# No -lgcc on purpose: a leftover *, / or % becomes an undefined
# __mulsi3 / __udivsi3 / __umodsi3 and the link fails.
%.elf: %.c crt0.s $(filter-out tables.h,$(wildcard *.h))
	$(RVCC) $(RVFLAGS) crt0.s $< -o $@
	riscv64-elf-size $@

# Generated tables (S3-1).
tables.h: s3_gen
	./s3_gen h > $@
tables.s: s3_gen
	./s3_gen s > $@
s3_check: s3_gen.c tables.h
# Always rebuilt, so switching between ida.h and LOW=1 (ida_low.h) is safe.
s3_ida: ida.h $(wildcard ida_low.h) tables.h FORCE
ifdef LOW
CFLAGS += -DLOW
endif
FORCE:
rv_ida.elf: ida.h tables.h

clean:
	$(RM) $(HOST) $(RV) tables.h tables.s
