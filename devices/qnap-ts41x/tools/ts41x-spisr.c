/*
 * ts41x-spisr: read or clear the block-protect bits of the TS-41x SPI NOR (ST M25P128).
 *
 * U-Boot's saveenv ends with "Protect ENV Sector": it sets the non-volatile BP bits in the
 * flash status register. Kernels that do not clear them for ST parts (QTS 3.4) then "write"
 * /dev/mtdblock4 without error while the chip ignores it. This talks to the Kirkwood SPI
 * controller through /dev/mem and only ever sends RDID, RDSR, WREN, WRSR and WRDI:
 * it cannot erase or program the array.
 *
 *   ts41x-spisr            print JEDEC id and status register
 *   ts41x-spisr --unlock   clear BP0-BP2 (and SRWD), then verify
 *
 * Build: arm-linux-gnueabi-gcc -O2 -static -o ts41x-spisr ts41x-spisr.c
 * Nothing else may use the flash while this runs (no fw_setenv, no firmware update).
 */
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

#define SPI_PHYS   0xf1010000UL   /* Kirkwood internal regs + 0x10000; controller at +0x600 */
#define IF_CTRL    (0x600 / 4)    /* bit 0: chip select asserted */
#define IF_CONFIG  (0x604 / 4)    /* bit 5: 16-bit transfers */
#define DATA_OUT   (0x608 / 4)
#define DATA_IN    (0x60c / 4)
#define INT_CAUSE  (0x610 / 4)    /* bit 0: transfer done */

#define RDID 0x9f
#define RDSR 0x05
#define WREN 0x06
#define WRDI 0x04
#define WRSR 0x01
#define SR_WIP  0x01
#define SR_WEL  0x02
#define SR_BP   0x1c
#define SR_SRWD 0x80

static volatile uint32_t *r;

static void die(const char *m) { fprintf(stderr, "ERROR: %s\n", m); exit(1); }

static void cs(int on)
{
	if (on) r[IF_CTRL] |= 1; else r[IF_CTRL] &= ~1u;
}

static uint8_t xfer(uint8_t b)
{
	int i;
	r[INT_CAUSE] = 0;
	r[DATA_OUT] = b;
	for (i = 0; i < 100000; i++)
		if (r[INT_CAUSE] & 1)
			return (uint8_t)r[DATA_IN];
	cs(0);
	die("SPI transfer timeout");
	return 0;
}

static void cmd(uint8_t c) { cs(1); xfer(c); cs(0); }

static uint8_t rdsr(void)
{
	uint8_t v;
	cs(1); xfer(RDSR); v = xfer(0); cs(0);
	return v;
}

static void show(uint8_t sr)
{
	printf("status 0x%02x: SRWD=%d BP=%d WEL=%d WIP=%d -> %s\n", sr, !!(sr & SR_SRWD),
	       (sr & SR_BP) >> 2, !!(sr & SR_WEL), !!(sr & SR_WIP),
	       (sr & SR_BP) ? "PROTECTED (writes are silently ignored)" : "not protected");
}

int main(int argc, char **argv)
{
	int unlock = argc == 2 && !strcmp(argv[1], "--unlock");
	int fd, i;
	uint8_t id[3], sr;
	void *map;

	if (argc > 2 || (argc == 2 && !unlock))
		die("usage: ts41x-spisr [--unlock]");
	fd = open("/dev/mem", O_RDWR | O_SYNC);
	if (fd < 0) die("cannot open /dev/mem (root?)");
	map = mmap(NULL, 4096, PROT_READ | PROT_WRITE, MAP_SHARED, fd, SPI_PHYS);
	if (map == MAP_FAILED) die("cannot map the SPI controller");
	r = map;
	if (r[IF_CONFIG] & (1 << 5)) die("controller is in 16-bit mode, not touching it");
	if (r[IF_CTRL] & 1) die("chip select already asserted: flash busy, try again");

	cs(1); xfer(RDID); for (i = 0; i < 3; i++) id[i] = xfer(0); cs(0);
	printf("jedec id %02x %02x %02x\n", id[0], id[1], id[2]);
	if (id[0] != 0x20 || id[1] != 0x20 || id[2] != 0x18)
		die("not an ST/Micron M25P128 (20 20 18): stopping");
	sr = rdsr();
	show(sr);
	if (!unlock)
		return 0;
	if (!(sr & (SR_BP | SR_SRWD))) { printf("nothing to do\n"); return 0; }

	cmd(WREN);
	if (!(rdsr() & SR_WEL)) die("write enable did not latch");
	cs(1); xfer(WRSR); xfer(0x00); cs(0);
	for (i = 0; i < 2000 && (rdsr() & SR_WIP); i++)
		usleep(1000);
	cmd(WRDI);
	sr = rdsr();
	show(sr);
	if (sr & SR_BP)
		die("BP bits still set: hardware write protect (W# pin) or SRWD; not fixable from software");
	printf("unlocked\n");
	return 0;
}
