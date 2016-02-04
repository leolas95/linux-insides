Proceso de arranque del kernel. Parte 2.
================================================================================

Primeros pasos en la configuración del kernel
--------------------------------------------------------------------------------
<<<<<<< HEAD:Arranque/linux-bootstrap-2.md
En el [artículo anterior](linux-bootstrap-1.md), comenzamos a explorar el
funcionamiento interno del kernel Linux, y vimos la parte inicial del código
de configuración del kernel. Nos detuvimos en la primera llamada a la función
`main` (la cual es la primera función escrita en lenguaje C), ubicada en
[arch/x86/boot/main.c](https://github.com/torvalds/linux/blob/master/arch/x86/boot/main.c).

En esta parte seguiremos aprendiendo acerca del código de configuración del
kernel, y también:
* Ver qué es el ̣̣`modo protegido`.
* Algunos arreglos para la transición a este.
* La inicialización del montón y de la consola.
* Detección de memoria, valicadción del CPU, inicialización del teclado.
* Y mucho más. 

Así que vayamos al grano.

Modo protegido
=======

We started to dive into linux kernel insides in the previous [part](linux-bootstrap-1.md) and saw the initial part of the kernel setup code. We stopped at the first call to the `main` function (which is the first function written in C) from [arch/x86/boot/main.c](https://github.com/torvalds/linux/blob/master/arch/x86/boot/main.c). 

In this part we will continue to research the kernel setup code and 
* see what `protected mode` is,
* some preparation for the transition into it,
* the heap and console initialization,
* memory detection, cpu validation, keyboard initialization
* and much much more.

So, Let's go ahead.

Protected mode
>>>>>>> upstream/master:Booting/linux-bootstrap-2.md
--------------------------------------------------------------------------------
Antes de que podamos movernos al [Modo largo](https://es.wikipedia.org/wiki/Modo_largo)
nativo de Intel64, el kernel debe pasar el CPU al modo protegido.

¿Pero qué es el [modo protegido](://es.wikipedia.org/wiki/Modo_protegido)? El
modo protegido fue añadido a la arquitectura x86 en 1982, y fue el modo
principal de los procesadores Intel, desde el [80286](://en.wikipedia.org/wiki/Intel_80286)
hasta que el Intel 64 y el modo largo llegaron.

La principal razón para alejarse del [modo real](http://wiki.osdev.org/Real_Mode),
es que hay un acceso limitado a la RAM. Como recordarás de la parte anterior,
solo hay 2<sup>20</sup> bytes, o 1 Megabyte, (a veces incluso solo 640 Kilobytes)
de RAM disponible en modo real.

El modo protegido trajo muchos cambios, pero el más importante es la diferencia
en la administración de la memoria. El bus de direccionamiento de 20 bits fue
reemplazado por uno de 32 bits. Este permitió el acceso a 4 Gigabytes de memoria,
en contra de 1 megabyte en el modo real. También se agregó soporte para el
[paginado de memoria](https://es.wikipedia.org/wiki/Paginaci%C3%B3n_de_memoria),
del cual pordrás leer más en los siguientes artículos.


La administración de memoria en modo protegido se divide en dos partes casi
independientes:

* Segmentación
* Paginación

Aquí solo veremos la segmentación. Discutiremos acerca de la paginación en los
siguientes artículos.

Como podrás leer en la parte anterior, las direcciones consisten de dos partes
en el modo real:

* Dirección base del segmento.
* Dirección relativa desde la base del segmento.

También vimos que podemos obtener la dirección física conociendo estas
dos partes, con:

```
DirecciónFísica = Segmento * 16 + DirecciónRelativa
```

La segmentación de memoria fue completamente rehecha en el modo protegido. Ya no hay segmentos
con un tamaño fijo de 64 Kilobytes. En cambio, el tamaño y la ubicación de cada segmento
es descrito por una estructura de datos asociada, llamada _Descriptor de segmento_. Los
descriptores de segmento están almacenados en una estructura de datos llamada
`Tabla Global de Descriptores (TGD)`

La TGD es una estructura que reside en memoria. No tiene un lugar fijo en esta, por lo que su
dirección es almacenada en un registro especial llamado `GDTR`. Más adelante
veremos la carga de la TGD en el código del kernel de Linux. Hay una operación
para cargarla en memoria, que sería algo como:

```assembly
lgdt gdt
```

Donde la instrucción `lgdt` carga la dirección base y el límite (tamaño) de
la TGD al registro `GDTR`. Este es un registro de 48 bits, y consiste de dos partes:

 * El tamaño (16 bits) de la TGD.
 * La dirección (32 bits) de la TGD.

Como se menciona arriba, la TGD contiene `descriptores de segmentos` que (valga la reduncancia)
describen segmentos de memoria. Cada descriptor tiene un tamaño de 64 bits.
El esquema general de un descriptor es el siguiente:

```
31          24        19      16              7            0
------------------------------------------------------------
|             | |B| |A|       | |   | |0|E|W|A|            |
| BASE 31:24  |G|/|L|V| LIMIT |P|DPL|S|  TYPE | BASE 23:16 | 4
|             | |D| |L| 19:16 | |   | |1|C|R|A|            |
------------------------------------------------------------
|                             |                            |
|        BASE 15:0            |       LÍMITE 15:0          | 0
|                             |                            |
------------------------------------------------------------
```

<<<<<<< HEAD:Arranque/linux-bootstrap-2.md
No te procupes, sé que luego del modo real, esto puede asustar un poco, pero
en realidad es fácil. Por ejemplo, LIMIT 15:0 significa que el bit 0-15 del descriptor
contiene el valor del límite. El resto está en LIMIT 16:19. Por lo tanto, el
tamaño del límite es de 0-19 (es decir, 20 bits). Echemos un vistazo a esto:


1. Limit[20 bits] está en los bits 0-15, 16-19. Este define `length_of_segment - 1`,
y depende de un bit llamado `G` (Granularidad).

  * Si `G` (el bit 55) es 0 y el límite del segmento es 0, el tamaño del
  segmento es de 1 Byte.
  * Si `G` es 1 y el límite del segmento es 0, el tamaño del segmento será
  de 4096 Bytes.
  * Si `G` es 0 y el límite del segmento es 0xfffff, el tamaño del segmento será
  de 1 Megabyte.
  * Si `G` es 1 y el límite del segmento es 0xfffff, el tamaño del segmento será
  de 4 Gigabytes.
  * if `G` is 1 and segment limit is 0xfffff, the size of the segment is 4 Gigabytes.

  Entonces, esto significa que si:
  * `G` es 0, `Limit` es interpretado en términos de 1 Byte, y el tamaño máximo
  del segmento puede ser 1 Megabyte.
  * `G` es 1, `Limit` es interpretado en terminos de 4096 Bytes = 4 KBytes = 1 página,
  y el tamaño máximo del segmento puede ser de 4 Gigabytes. De hecho, lo que realmente
  pasa es que cuando `G` es 1, el valor de `Limit` es desplazado a la izquierda
  12 bits. Por lo que 20 bits + 12 bits = 32 bits, y 2<sup>32</sup> = 4 Gigabytes.

2. Base[32 bits] está en los bits 0-15, 32-39 y 56-63. Este define la dirección
física de la ubicación inicial del segmento.

3. Type/Attribute (40-47 bits) define el tipo del segmento, en cierta forma accede
a él.
  * La bandera `S` en el bit 44 especifica el tipo del descriptor. Si `S` es 0,
  entonces este segmento es del sistema, en cambio si `S` es 1,
  entonces este segmento es de código o datos.(los segmentos de pila son
  segmentos de datos que deben ser de lectura/escritura).

Para determinar si el segmento es de código o datos, podemos revisar su
atributo `Ex` (el bit 43), marcado como 0 en el diagrama de arriba. Si este es
0, entonces el segmento es de datos; de otro modo, es de código.

Un segmento puede ser de alguno de los siguientes tipos:
=======
Don't worry, I know it looks a little scary after real mode, but it's easy. For example LIMIT 15:0 means that bit 0-15 of the Descriptor contain the value for the limit. The rest of it is in LIMIT 19:16. So, the size of Limit is 0-19 i.e 20-bits. Let's take a closer look at it:
>>>>>>> upstream/master:Booting/linux-bootstrap-2.md

```
|           Tipo de campo     | Tipo del descriptor   | Descripción
|-----------------------------|-----------------------|------------------
| Decimal                     |                       |
|             0    E    W   A |                       |
| 0           0    0    0   0 | Datos                 | Solo-Lectura
| 1           0    0    0   1 | Datos                 | Solo-Lectura, accesado
| 2           0    0    1   0 | Datos                 | Lectura/Escritura
| 3           0    0    1   1 | Datos                 | Lectura/Escritura, accesado
| 4           0    1    0   0 | Datos                 | Solo-Lectura, expandido abajo
| 5           0    1    0   1 | Datos                 | Solo-Lectura, expandido abajo, accesado
| 6           0    1    1   0 | Datos                 | Lectura/Escritura, expandido abajo
| 7           0    1    1   1 | Datos                 | Lectura/Escritura, expandido abajo, accesado
|                  C    R   A |                       |
| 8           1    0    0   0 | Código                | Solo-Ejecución
| 9           1    0    0   1 | Código                | Solo-Ejecución, accesado
| 10          1    0    1   0 | Código                | Ejecución/Lectura
| 11          1    0    1   1 | Código                | Ejecución/Lectura, accesado
| 12          1    1    0   0 | Código                | Solo-Ejecución, conforme
| 14          1    1    0   1 | Código                | Solo-Ejecución, conforme, accesado
| 13          1    1    1   0 | Código                | Ejecución/Lectura, conforme
| 15          1    1    1   1 | Código                | Ejecución/Lectura, conforme, accesado
```

Como podemos ver, el primer bit (el 43) es `0` para un segmento de _datos_, y
`1` para uno de _código_. Los siguientes tres bits (40, 41, 42, 43) son, o bien
`EWA` (*E*xpansion *W*ritable *A*ccessible / *E*xpansión *E*scritura *A*ccesible)
o CRA (*C*onforming *R*eadable *A*ccessible / *C*onforme *L*ectura *A*ccesible).

  * si `E` (el bit 42) es 0, expandir hacia arriba, de otro modo, expandir hacia
  abajo. Puedes leer más [aquí](http://www.sudleyplace.com/dpmione/expanddown.html).

  * si W (el bit 41) (para **segmentos de datos**) es 1, el acceso para escritura está
  permitido, de otro modo, no lo está. Debes notar que el acceso de lectura siempre
  está permitido en segmentos de datos

  * A (el bit 40) - Indica si el segmento es accedido por el procesador o no.

  * C (el bit 43) es el bit de conformidad (para selectores de código). Si `C`
  es 1, el segmento de código se puede ejecutar desde un nivel de privilegios
  más bajo, por ejemplo, desde el nivel del usuario. Si `C` es 0, el segmento
  solo se podrá ejecutar desde el mismo nivel de privilegios.

  * si R (el bit 41) (para **segmentos de código**) es 1, se permite el acceso
  de lectura al segmento, de otro modo, no se permite. El permiso de escritura
  nunca está permitido en segmentos de código.

<<<<<<< HEAD:Arranque/linux-bootstrap-2.md
4. DPL [2 bits](https://courses.engr.illinois.edu/ece391/fa2014/references/descriptors.pdf)
está en los bits 45-46. este define el nivel de privilegio del segmento. Puede ir
de 0 hasta 3, donde 0 es el más privilegiado.
=======
As we can see the first bit(bit 43) is `0` for a _data_ segment and `1` for a _code_ segment. The next three bits(40, 41, 42, 43) are either `EWA`(*E*xpansion *W*ritable *A*ccessible) or CRA(*C*onforming *R*eadable *A*ccessible).
  * if E(bit 42) is 0, expand up other wise expand down. Read more [here](http://www.sudleyplace.com/dpmione/expanddown.html).
  * if W(bit 41)(for Data Segments) is 1, write access is allowed otherwise not. Note that read access is always allowed on data segments.
  * A(bit 40) - Whether the segment is accessed by processor or not.
  * C(bit 43) is conforming bit(for code selectors). If C is 1, the segment code can be executed from a lower level privilege e.g. user level. If C is 0, it can only be executed from the same privilege level.
  * R(bit 41)(for code segments). If 1 read access to segment is allowed otherwise not. Write access is never allowed to code segments.
>>>>>>> upstream/master:Booting/linux-bootstrap-2.md

5. La bandera `P` (el bit 47) indica si el segmento está presente en memoria o
no. Si `P` es 0, el segmento estará presente como _invalid_ y el procesador
se rehusará a leer este segmento.

6. La bandera `AVL` (el bit 52) indica los bits disponibles y los reservados.
En Linux, es ignorada.

7. La bandera `L` (el bit 53) indica si un segmento de código contiene
código nativo de 64 bits. Si es 1 entonces el segmento de código se ejecuta en
modo de 64 bits.

8. La bandera `D/B` (Default/Big) (el bit 54) representa el tamaño del operando;
16/32 bits. Si está encendida, entonces este será de 32 bits, de otro modo, será de 16.


Segment registers don't contain the base address of the segment as in real mode. Instead they contain a special structure - `Segment Selector`. Each Segment Descriptor has an associated Segment Selector. `Segment Selector` is a 16-bit structure:

```
-----------------------------
|       Index    | TI | RPL |
-----------------------------
```

Where,
* **Index** shows the index number of the descriptor in the GDT.
* **TI**(Table Indicator) shows where to search for the descriptor. If it is 0 then search in the Global Descriptor Table(GDT) otherwise it will look in Local Descriptor Table(LDT).
* And **RPL** is Requester's Privilege Level.

Every segment register has a visible and hidden part.
* Visible - Segment Selector is stored here
* Hidden - Segment Descriptor(base, limit, attributes, flags)
 
The following steps are needed to get the physical address in the protected mode:

* The segment selector must be loaded in one of the segment registers
* The CPU tries to find a segment descriptor by GDT address + Index from selector and load the descriptor into the *hidden* part of the segment register
* Base address (from segment descriptor) + offset will be the linear address of the segment which is the physical address (if paging is disabled).

Schematically it will look like this:

![linear address](http://oi62.tinypic.com/2yo369v.jpg)

The algorithm for the transition from real mode into protected mode is:

* Disable interrupts
* Describe and load GDT with `lgdt` instruction
* Set PE (Protection Enable) bit in CR0 (Control Register 0)
* Jump to protected mode code

We will see the complete transition to protected mode in the linux kernel in the next part, but before we can move to protected mode, we need to do some more preparations.

Let's look at [arch/x86/boot/main.c](https://github.com/torvalds/linux/blob/master/arch/x86/boot/main.c). We can see some routines there which perform keyboard initialization, heap initialization, etc... Let's take a look.

Copying boot parameters into the "zeropage"
--------------------------------------------------------------------------------

We will start from the `main` routine in "main.c". First function which is called in `main` is [`copy_boot_params(void)`](https://github.com/torvalds/linux/blob/master/arch/x86/boot/main.c#L30). It copies the kernel setup header into the field of the `boot_params` structure which is defined in the [arch/x86/include/uapi/asm/bootparam.h](https://github.com/torvalds/linux/blob/master/arch/x86/include/uapi/asm/bootparam.h#L113).

The `boot_params` structure contains the `struct setup_header hdr` field. This structure contains the same fields as defined in [linux boot protocol](https://www.kernel.org/doc/Documentation/x86/boot.txt) and is filled by the boot loader and also at kernel compile/build time. `copy_boot_params` does two things:

1. Copies `hdr` from [header.S](https://github.com/torvalds/linux/blob/master/arch/x86/boot/header.S#L281) to the `boot_params` structure in `setup_header` field

2. Updates pointer to the kernel command line if the kernel was loaded with the old command line protocol.

Note that it copies `hdr` with `memcpy` function which is defined in the [copy.S](https://github.com/torvalds/linux/blob/master/arch/x86/boot/copy.S) source file. Let's have a look inside:

```assembly
GLOBAL(memcpy)
	pushw	%si
	pushw	%di
	movw	%ax, %di
	movw	%dx, %si
	pushw	%cx
	shrw	$2, %cx
	rep; movsl
	popw	%cx
	andw	$3, %cx
	rep; movsb
	popw	%di
	popw	%si
	retl
ENDPROC(memcpy)
```

Yeah, we just moved to C code and now assembly again :) First of all we can see that `memcpy` and other routines which are defined here, start and end with the two macros: `GLOBAL` and `ENDPROC`. `GLOBAL` is described in [arch/x86/include/asm/linkage.h](https://github.com/torvalds/linux/blob/master/arch/x86/include/asm/linkage.h) which defines `globl` directive and the label for it. `ENDPROC` is described in [include/linux/linkage.h](https://github.com/torvalds/linux/blob/master/include/linux/linkage.h) which marks the `name` symbol as a function name and ends with the size of the `name` symbol.

Implementation of `memcpy` is easy. At first, it pushes values from the `si` and `di` registers to the stack to preserve their values because they will change during the `memcpy`. `memcpy` (and other functions in copy.S) use `fastcall` calling conventions. So it gets its incoming parameters from the `ax`, `dx` and `cx` registers.  Calling `memcpy` looks like this:

```c
memcpy(&boot_params.hdr, &hdr, sizeof hdr);
```

So,
* `ax` will contain the address of the `boot_params.hdr` in bytes
* `dx` will contain the address of `hdr` in bytes
* `cx` will contain the size of `hdr` in bytes.

`memcpy` puts the address of `boot_params.hdr` into `si` and saves the size on the stack. After this it shifts to the right on 2 size (or divide on 4) and copies from `si` to `di` by 4 bytes. After this we restore the size of `hdr` again, align it by 4 bytes and copy the rest of the bytes from `si` to `di` byte by byte (if there is more). Restore `si` and `di` values from the stack in the end and after this copying is finished.

Console initialization
--------------------------------------------------------------------------------

After `hdr` is copied into `boot_params.hdr`, the next step is console initialization by calling the `console_init` function which is defined in [arch/x86/boot/early_serial_console.c](https://github.com/torvalds/linux/blob/master/arch/x86/boot/early_serial_console.c).

It tries to find the `earlyprintk` option in the command line and if the search was successful, it parses the port address and baud rate of the serial port and initializes the serial port. Value of `earlyprintk` command line option can be one of these:

	* serial,0x3f8,115200
	* serial,ttyS0,115200
	* ttyS0,115200

After serial port initialization we can see the first output:

```C
if (cmdline_find_option_bool("debug"))
		puts("early console in setup code\n");
```

The definition of `puts` is in [tty.c](https://github.com/torvalds/linux/blob/master/arch/x86/boot/tty.c). As we can see it prints character by character in a loop by calling the `putchar` function. Let's look into the `putchar` implementation:

```C
void __attribute__((section(".inittext"))) putchar(int ch)
{
	if (ch == '\n')
		putchar('\r');

	bios_putchar(ch);

	if (early_serial_base != 0)
		serial_putchar(ch);
}
```

`__attribute__((section(".inittext")))` means that this code will be in the `.inittext` section. We can find it in the linker file [setup.ld](https://github.com/torvalds/linux/blob/master/arch/x86/boot/setup.ld#L19).

First of all, `putchar` checks for the `\n` symbol and if it is found, prints `\r` before. After that it outputs the character on the VGA screen by calling the BIOS with the `0x10` interrupt call:

```C
static void __attribute__((section(".inittext"))) bios_putchar(int ch)
{
	struct biosregs ireg;

	initregs(&ireg);
	ireg.bx = 0x0007;
	ireg.cx = 0x0001;
	ireg.ah = 0x0e;
	ireg.al = ch;
	intcall(0x10, &ireg, NULL);
}
```

Here `initregs` takes the `biosregs` structure and first fills `biosregs` with zeros using the `memset` function and then fills it with register values.

```C
	memset(reg, 0, sizeof *reg);
	reg->eflags |= X86_EFLAGS_CF;
	reg->ds = ds();
	reg->es = ds();
	reg->fs = fs();
	reg->gs = gs();
```

Let's look at the [memset](https://github.com/torvalds/linux/blob/master/arch/x86/boot/copy.S#L36) implementation:

```assembly
GLOBAL(memset)
	pushw	%di
	movw	%ax, %di
	movzbl	%dl, %eax
	imull	$0x01010101,%eax
	pushw	%cx
	shrw	$2, %cx
	rep; stosl
	popw	%cx
	andw	$3, %cx
	rep; stosb
	popw	%di
	retl
ENDPROC(memset)
```

As you can read above, it uses the `fastcall` calling conventions like the `memcpy` function, which means that the function gets parameters from `ax`, `dx` and `cx` registers.

Generally `memset` is like a memcpy implementation. It saves the value of the `di` register on the stack and puts the `ax` value into `di` which is the address of the `biosregs` structure. Next is the `movzbl` instruction, which copies the `dl` value to the low 2 bytes of the `eax` register. The remaining 2 high bytes  of `eax` will be filled with zeros.

The next instruction multiplies `eax` with `0x01010101`. It needs to because `memset` will copy 4 bytes at the same time. For example, we need to fill a structure with `0x7` with memset. `eax` will contain `0x00000007` value in this case. So if we multiply `eax` with `0x01010101`, we will get `0x07070707` and now we can copy these 4 bytes into the structure. `memset` uses `rep; stosl` instructions for copying `eax` into `es:di`.

The rest of the `memset` function does almost the same as `memcpy`.

After the `biosregs` structure is filled with `memset`, `bios_putchar` calls the [0x10](http://www.ctyme.com/intr/rb-0106.htm) interrupt which prints a character. Afterwards it checks if the serial port was initialized or not and writes a character there with [serial_putchar](https://github.com/torvalds/linux/blob/master/arch/x86/boot/tty.c#L30) and `inb/outb` instructions if it was set.

Heap initialization
--------------------------------------------------------------------------------

After the stack and bss section were prepared in [header.S](https://github.com/torvalds/linux/blob/master/arch/x86/boot/header.S) (see previous [part](linux-bootstrap-1.md)), the kernel needs to initialize the [heap](https://github.com/torvalds/linux/blob/master/arch/x86/boot/main.c#L116) with the [`init_heap`](https://github.com/torvalds/linux/blob/master/arch/x86/boot/main.c#L116) function.

First of all `init_heap` checks the [`CAN_USE_HEAP`](https://github.com/torvalds/linux/blob/master/arch/x86/include/uapi/asm/bootparam.h#L21) flag from the [`loadflags`](https://github.com/torvalds/linux/blob/master/arch/x86/boot/header.S#L321) in the kernel setup header and calculates the end of the stack if this flag was set:

```C
	char *stack_end;

	if (boot_params.hdr.loadflags & CAN_USE_HEAP) {
		asm("leal %P1(%%esp),%0"
		    : "=r" (stack_end) : "i" (-STACK_SIZE));
```

or in other words `stack_end = esp - STACK_SIZE`.

Then there is the `heap_end` calculation:
```c
	heap_end = (char *)((size_t)boot_params.hdr.heap_end_ptr + 0x200);
```
which means `heap_end_ptr` or `_end` + `512`(`0x200h`). The last check is whether `heap_end` is greater than `stack_end`. If it is then `stack_end` is assigned to `heap_end` to make them equal.

Now the heap is initialized and we can use it using the `GET_HEAP` method. We will see how it is used, how to use it and how the it is implemented in the next posts.

CPU validation
--------------------------------------------------------------------------------

The next step as we can see is cpu validation by `validate_cpu` from [arch/x86/boot/cpu.c](https://github.com/torvalds/linux/blob/master/arch/x86/boot/cpu.c).

It calls the [`check_cpu`](https://github.com/torvalds/linux/blob/master/arch/x86/boot/cpucheck.c#L102) function and passes cpu level and required cpu level to it and checks that the kernel launches on the right cpu level.
```c
check_cpu(&cpu_level, &req_level, &err_flags);
	if (cpu_level < req_level) {
    ...
	return -1;
	}
```
`check_cpu` checks the cpu's flags, presence of [long mode](http://en.wikipedia.org/wiki/Long_mode) in case of x86_64(64-bit) CPU, checks the processor's vendor and makes preparation for certain vendors like turning off SSE+SSE2 for AMD if they are missing, etc.

Memory detection
--------------------------------------------------------------------------------

The next step is memory detection by the `detect_memory` function. `detect_memory` basically provides a map of available RAM to the cpu. It uses different programming interfaces for memory detection like `0xe820`, `0xe801` and `0x88`. We will see only the implementation of **0xE820** here.

Let's look into the `detect_memory_e820` implementation from the [arch/x86/boot/memory.c](https://github.com/torvalds/linux/blob/master/arch/x86/boot/memory.c) source file. First of all, the `detect_memory_e820` function initializes the `biosregs` structure as we saw above and fills registers with special values for the `0xe820` call:

```assembly
	initregs(&ireg);
	ireg.ax  = 0xe820;
	ireg.cx  = sizeof buf;
	ireg.edx = SMAP;
	ireg.di  = (size_t)&buf;
```

* `ax` contains the number of the function (0xe820 in our case)
* `cx` register contains size of the buffer which will contain data about memory
* `edx` must contain the `SMAP` magic number
* `es:di` must contain the address of the buffer which will contain memory data
* `ebx` has to be zero.

Next is a loop where data about the memory will be collected. It starts from the call of the `0x15` BIOS interrupt, which writes one line from the address allocation table. For getting the next line we need to call this interrupt again (which we do in the loop). Before the next call `ebx` must contain the value returned previously:

```C
	intcall(0x15, &ireg, &oreg);
	ireg.ebx = oreg.ebx;
```

Ultimately, it does iterations in the loop to collect data from the address allocation table and writes this data into the `e820entry` array:

* start of memory segment
* size  of memory segment
* type of memory segment (which can be reserved, usable and etc...).

You can see the result of this in the `dmesg` output, something like:

```
[    0.000000] e820: BIOS-provided physical RAM map:
[    0.000000] BIOS-e820: [mem 0x0000000000000000-0x000000000009fbff] usable
[    0.000000] BIOS-e820: [mem 0x000000000009fc00-0x000000000009ffff] reserved
[    0.000000] BIOS-e820: [mem 0x00000000000f0000-0x00000000000fffff] reserved
[    0.000000] BIOS-e820: [mem 0x0000000000100000-0x000000003ffdffff] usable
[    0.000000] BIOS-e820: [mem 0x000000003ffe0000-0x000000003fffffff] reserved
[    0.000000] BIOS-e820: [mem 0x00000000fffc0000-0x00000000ffffffff] reserved
```

Keyboard initialization
--------------------------------------------------------------------------------

The next step is the initialization of the keyboard with the call of the [`keyboard_init()`](https://github.com/torvalds/linux/blob/master/arch/x86/boot/main.c#L65) function. At first `keyboard_init` initializes registers using the `initregs` function and calling the [0x16](http://www.ctyme.com/intr/rb-1756.htm) interrupt for getting the keyboard status.
```c
	initregs(&ireg);
	ireg.ah = 0x02;		/* Get keyboard status */
	intcall(0x16, &ireg, &oreg);
	boot_params.kbd_status = oreg.al;
```
After this it calls [0x16](http://www.ctyme.com/intr/rb-1757.htm) again to set repeat rate and delay.
```c
	ireg.ax = 0x0305;	/* Set keyboard repeat rate */
	intcall(0x16, &ireg, NULL);
```

Querying
--------------------------------------------------------------------------------

The next couple of steps are queries for different parameters. We will not dive into details about these queries, but will get back to it in later parts. Let's take a short look at these functions:

The [query_mca](https://github.com/torvalds/linux/blob/master/arch/x86/boot/mca.c#L18) routine calls the [0x15](http://www.ctyme.com/intr/rb-1594.htm) BIOS interrupt to get the machine model number, sub-model number, BIOS revision level, and other hardware-specific attributes:

```c
int query_mca(void)
{
	struct biosregs ireg, oreg;
	u16 len;

	initregs(&ireg);
	ireg.ah = 0xc0;
	intcall(0x15, &ireg, &oreg);

	if (oreg.eflags & X86_EFLAGS_CF)
		return -1;	/* No MCA present */

	set_fs(oreg.es);
	len = rdfs16(oreg.bx);

	if (len > sizeof(boot_params.sys_desc_table))
		len = sizeof(boot_params.sys_desc_table);

	copy_from_fs(&boot_params.sys_desc_table, oreg.bx, len);
	return 0;
}
```

It fills  the `ah` register with `0xc0` and calls the `0x15` BIOS interruption. After the interrupt execution it checks  the [carry flag](http://en.wikipedia.org/wiki/Carry_flag) and if it is set to 1, the BIOS doesn't support (**MCA**)[https://en.wikipedia.org/wiki/Micro_Channel_architecture]. If carry flag is set to 0, `ES:BX` will contain a pointer to the system information table, which looks like this:

```
Offset	Size	Description	)
 00h	WORD	number of bytes following
 02h	BYTE	model (see #00515)
 03h	BYTE	submodel (see #00515)
 04h	BYTE	BIOS revision: 0 for first release, 1 for 2nd, etc.
 05h	BYTE	feature byte 1 (see #00510)
 06h	BYTE	feature byte 2 (see #00511)
 07h	BYTE	feature byte 3 (see #00512)
 08h	BYTE	feature byte 4 (see #00513)
 09h	BYTE	feature byte 5 (see #00514)
---AWARD BIOS---
 0Ah  N BYTEs	AWARD copyright notice
---Phoenix BIOS---
 0Ah	BYTE	??? (00h)
 0Bh	BYTE	major version
 0Ch	BYTE	minor version (BCD)
 0Dh  4 BYTEs	ASCIZ string "PTL" (Phoenix Technologies Ltd)
---Quadram Quad386---
 0Ah 17 BYTEs	ASCII signature string "Quadram Quad386XT"
---Toshiba (Satellite Pro 435CDS at least)---
 0Ah  7 BYTEs	signature "TOSHIBA"
 11h	BYTE	??? (8h)
 12h	BYTE	??? (E7h) product ID??? (guess)
 13h  3 BYTEs	"JPN"
 ```

Next we call the `set_fs` routine and pass the value of the `es` register to it. The implementation of `set_fs` is pretty simple:

```c
static inline void set_fs(u16 seg)
{
	asm volatile("movw %0,%%fs" : : "rm" (seg));
}
```

This function contains inline assembly which gets the value of the `seg` parameter and puts it into the `fs` register. There are many functions in [boot.h](https://github.com/torvalds/linux/blob/master/arch/x86/boot/boot.h) like `set_fs`, for example `set_gs`, `fs`, `gs` for reading a value in it etc...

At the end of `query_mca` it just copies the table pointed to by `es:bx` to the `boot_params.sys_desc_table`.

The next step is getting [Intel SpeedStep](http://en.wikipedia.org/wiki/SpeedStep) information by calling the `query_ist` function. First of all it checks the CPU level and if it is correct, calls `0x15` for getting info and saves the result to `boot_params`.

The following [query_apm_bios](https://github.com/torvalds/linux/blob/master/arch/x86/boot/apm.c#L21) function gets [Advanced Power Management](http://en.wikipedia.org/wiki/Advanced_Power_Management) information from the BIOS. `query_apm_bios` calls the `0x15` BIOS interruption too, but with `ah` = `0x53` to check `APM` installation. After the `0x15` execution, `query_apm_bios` functions check the `PM` signature (it must be `0x504d`), carry flag (it must be 0 if `APM` supported) and value of the `cx` register (if it's 0x02, protected mode interface is supported).

Next it calls `0x15` again, but with `ax = 0x5304` for disconnecting the `APM` interface and connecting the 32-bit protected mode interface. In the end it fills `boot_params.apm_bios_info` with values obtained from the BIOS.

Note that `query_apm_bios` will be executed only if `CONFIG_APM` or `CONFIG_APM_MODULE` was set in the configuration file:

```C
#if defined(CONFIG_APM) || defined(CONFIG_APM_MODULE)
	query_apm_bios();
#endif
```

The last is the [`query_edd`](https://github.com/torvalds/linux/blob/master/arch/x86/boot/edd.c#L122) function, which queries `Enhanced Disk Drive` information from the BIOS. Let's look into the `query_edd` implementation.

First of all it reads the [edd](https://github.com/torvalds/linux/blob/master/Documentation/kernel-parameters.txt#L1023) option from the kernel's command line and if it was set to `off` then `query_edd` just returns.

If EDD is enabled, `query_edd` goes over BIOS-supported hard disks and queries EDD information in the following loop:

```C
	for (devno = 0x80; devno < 0x80+EDD_MBR_SIG_MAX; devno++) {
		if (!get_edd_info(devno, &ei) && boot_params.eddbuf_entries < EDDMAXNR) {
			memcpy(edp, &ei, sizeof ei);
			edp++;
			boot_params.eddbuf_entries++;
		}
		...
		...
		...
```

where `0x80` is the first hard drive and the value of `EDD_MBR_SIG_MAX` macro is 16. It collects data into the array of [edd_info](https://github.com/torvalds/linux/blob/master/include/uapi/linux/edd.h#L172) structures. `get_edd_info` checks that EDD is present by invoking the `0x13` interrupt with `ah` as `0x41` and if EDD is present, `get_edd_info` again calls the `0x13` interrupt, but with `ah` as `0x48` and `si` containing the address of the buffer where EDD information will be stored.

Conclusion
--------------------------------------------------------------------------------

This is the end of the second part about Linux kernel insides. In the next part we will see video mode setting and the rest of preparations before transition to protected mode and directly transitioning into it.

If you have any questions or suggestions write me a comment or ping me at [twitter](https://twitter.com/0xAX).

**Please note that English is not my first language, And I am really sorry for any inconvenience. If you find any mistakes please send me a PR to [linux-insides](https://github.com/0xAX/linux-internals).**

Links
--------------------------------------------------------------------------------

* [Protected mode](http://en.wikipedia.org/wiki/Protected_mode)
* [Protected mode](http://wiki.osdev.org/Protected_Mode)
* [Long mode](http://en.wikipedia.org/wiki/Long_mode)
* [Nice explanation of CPU Modes with code](http://www.codeproject.com/Articles/45788/The-Real-Protected-Long-mode-assembly-tutorial-for)
* [How to Use Expand Down Segments on Intel 386 and Later CPUs](http://www.sudleyplace.com/dpmione/expanddown.html)
* [earlyprintk documentation](http://lxr.free-electrons.com/source/Documentation/x86/earlyprintk.txt)
* [Kernel Parameters](https://github.com/torvalds/linux/blob/master/Documentation/kernel-parameters.txt)
* [Serial console](https://github.com/torvalds/linux/blob/master/Documentation/serial-console.txt)
* [Intel SpeedStep](http://en.wikipedia.org/wiki/SpeedStep)
* [APM](https://en.wikipedia.org/wiki/Advanced_Power_Management)
* [EDD specification](http://www.t13.org/documents/UploadedDocuments/docs2004/d1572r3-EDD3.pdf)
* [TLDP documentation for Linux Boot Process](http://www.tldp.org/HOWTO/Linux-i386-Boot-Code-HOWTO/setup.html) (old)
* [Previous Part](linux-bootstrap-1.md)

