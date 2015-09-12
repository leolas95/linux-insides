Proceso de arranque del kernel. Parte 1
==================================================================================

Desde el cargador de arranque al kernel
----------------------------------------------------------------------------------

Si has leído mis [artículos de blog recientes](http://0xax.blogspot.com/search/label/asm)
puedes ver que hace algún tiempo empecé a involucrarme con programación a bajo nivel.
Escribí algunos artículos acerca de programación en ensamblador X86_64 para Linux.
Al mismo tiempo, empecé a profundizar en el código fuente de Linux. Tengo un
gran interés en comprender cómo funcionan las cosas a bajo nivel, cómo se
ejecutan los programas en mi computadora, cómo se localizan(!)
en memoria, cómo el kernel administra los procesos y la memoria, cómo la
pila(!) de red trabaja a bajo nivel, y muchas otras cosas. Por lo tanto, decidí
escribir otra serie de artículos acerca del kernel Linux para X86_64.

Es importante notar que yo no soy un completo profesional del kernel, y que mi
trabajo no es escribir código del kernel. Es solo un pasatiempo. Simplemente me
gustan las cosas a bajo nivel, y para mí es interesante ver cómo todas estas cosas
funcionan. Por lo tanto, si notas algo confuso, o tienes alguna duda/observación,
no dudes en contactarme(!) en [twiter](@0xAX), enviarme un [correo](mailto:anotherworldofworld@gmail.com)
o simplemente reporta un [problema](https://github.com/0xAX/linux-insides/issues/new). Lo apreciaría mucho.
Todos los artículos también estarán accesibles por [linux-insides](https://github.com/0xAX/linux-insides),
y si encuentras algún error con el contenido del artículo
o con mi gramática, sientete libre de enviar un pull request.

*Es importante notar que esto no es una documentación oficial, simplemente es compartir y ganar conocimiento.*

**Aptitudes requeridas:**

* Comprender código en lenguaje C
* Comprender código en lenguaje ensamblador (sintaxis de AT&T)


De cualquier modo, si acabas de empezar a aprender algunas herramientas(!!), trataré de explicar algunas partes durante este y los siguientes artículos. Bien, terminada la pequeña introducción,
ya podemos empezar a profundizar en el kernel y cosas de bajo nivel.

Todo el código es del kernel -3.18. Si hay algún cambio, actualizaré el artículo apropiadamente.

El mágico botón de encendido, ¿Qué ocurre luego?
--------------------------------------------------------------------------------

A pesar de que estos son una serie de artículos acerca del kernel Linux, no
empezaremos desde el código del kernel (por lo menos no en este párrafo). Ok,
presionaste el mágico botón de encendido en tu laptop o computador de
escritorio y este ha empezado a trabajar. Luego de que la tarjeta madre
envía una señal a la fuente de poder, esta provee a la computadora con
la cantidad debida de electricidad. Una vez que la tarjeta madre recibe la señal
correcta de energía, esta intenta iniciar el CPU. Este reinicia todos los
datos residuales en sus registros y establece valores predefinidos para
cada uno de ellos.

La línea de CPUs 80386 (y los posteriores a esta) establecen una serie de datos
predefinidos en los registros del CPU luego de un reinicio:

```
IP          0xfff0
CS selector 0xf000
CS base     0xffff0000
```

El procesador comienza a trabajar en [modo real](https://es.wikipedia.org/wiki/Modo_real).
Vamos a repasar un poco para entender cómo funciona la segmentación de memoria
en este modo. El modo real está soportado en todos los procesadores compatibles
con la arquitectura x86, desde el [8086](https://es.wikipedia.org/wiki/Intel_8086_y_8088)
hasta los modernos CPUs Intel de 64 bits. El procesador 8086 tenía un bus de
direcciones de 20 bits, lo que significa que podía trabajar con 0-2^20
bytes de dirección de espacio (1 megabyte). Pero este solo tenía registros de
16 bits, con los cuales la dirección máxima es 2^16, o 0xffff (64 Kilobytes).
La [Segmentación de memoria](https://es.wikipedia.org/wiki/Segmentaci%C3%B3n_de_memoria)
sirve para hacer uso de todo el espacio de dirección disponible. Toda la
memoria es dividida en pequeños segmentos de tamaño fijo de 65535 bytes, o 64
64 KB. Como no podemos direccionar memoria más allá de 64 Kb con registros de
16 bits, se ideó un método alternativo. Una dirección consta de dos partes:
el inicio de la dirección del segmento y un [*offset*](https://es.wikipedia.org/wiki/Offset_%28inform%C3%A1tica%29).
Para obtener la dirección física en memoria, debemos multiplicar la parte del
segmento por 16 y sumar la parte del *offset*:

```
PhysicalAddress = Segment * 16 + Offset
```

Por ejemplo, si `CS:IP` es `0x2000:0x0010`, la dirección física correspondiente
será:

```python
>>> hex((0x2000 << 4) + 0x0010)
'0x20010'
```

Pero si tomamos la parte más larga del segmento de memoria y el *offset*: 
`0xffff:0xffff`, este será:

```python
>>> hex((0xffff << 4) + 0xffff)
'0x10ffef'
```

que son 65519 bytes del primer megabyte. Como solo un megabyte es accesible en
el modo real, `0x10ffef` se convierte en `0x00ffef` con [A20](https://en.wikipedia.org/wiki/A20_line)desactivado.

Muy bien, ahora sabemos acerca del modo real y el direccionamiento de memoria.
Volvamos a los valores de los registros del CPU luego del reinicio:

El registro `CS` consiste de dos partes: el selector visible del segmento y una
dirección base oculta. Conocemos el `CS` base predefinidoy el valor de `IP`,
por lo que la siguiente dirección lógica será:

```
0xffff0000:0xfff0
```

La dirección inicial se forma sumando la dirección base al valor en el
registro `EIP`:

```python
>>> 0xffff0000 + 0xfff0
'0xfffffff0'
```
Obtenemos '0xfffffff0', que son 4GB - 16 bytes. Este punto es llamado [Vector de reinicio](https://en.wikipedia.org/wiki/Reset_vector).
Esta es la dirección de memoria en la que el CPU espera encontrar la primera
instrucción a ejecutar luego del reinicio. Esta contiene una instrucción
[jump](https://en.wikipedia.org/wiki/JMP_%28x86_instruction%29), que usualmente
apunta al punto de entrada de la BIOS. Por ejemplo, si miramos en el código
fuente de [coreboot](http://www.coreboot.org/), veremos lo siguiente:

```assembly
	.section ".reset"
	.code16
.globl	reset_vector
reset_vector:
	.byte  0xe9
	.int   _start - ( . + 2 )
	...
```

Aquí podemos ver el que el [opcode](http://ref.x86asm.net/coder32.html#xE9) de la
instrucción jump - 0xe9 apunta a la dirección `_start - ( . + 2)`,(!!) y también
podemos ver que la sección `reset` es de 16 bytes, y comienza en `0xfffffff0`:

```
SECTIONS {
	_ROMTOP = 0xfffffff0;
	. = _ROMTOP;
	.reset . : {
		*(.reset)
		. = 15 ;
		BYTE(0x00);
	}
}
```

Ahora el BIOS inicia: luego de inicializar y verificar el hardware, necesita
encontrar un dispositivo de arranque. Una orden de arranque es almacenada en
la configuración del BIOS, controlando desde cuáles dispositivos el kernel
intenta arrancar. Cuando se intenta arrancar desde un disco duro, el BIOS
intenta encontrar un [sector de arranque](https://es.wikipedia.org/wiki/Bloque_de_arranque).
En los discos duros particionados con un [MBR](https://es.wikipedia.org/wiki/Registro_de_arranque_principal),
el sector de arranque es almacenado en los primeros 446 bytes del primer sector
(el cual es de 512 bytes). Los últimos dos bytes del primer sector son `0x55`
y `0xaa`, lo que le indica al BIOS que el dispositivo es de arranque. Por
ejemplo:

```assembly
;
; Note: this example is written in Intel Assembly syntax
;
[BITS 16]
[ORG  0x7c00]

boot:
    mov al, '!'
    mov ah, 0x0e
    mov bh, 0x00
    mov bl, 0x07

    int 0x10
    jmp $

times 510-($-$$) db 0

db 0x55
db 0xaa
```

Compilar y ejecutar con:

```
nasm -f bin boot.nasm && qemu-system-x86_64 boot
```

Esto le ordenará al [QEMU](http://qemu.org) de usar el archivo binario `boot`
que acabamos de crear arriba como una imágen de disco. Como el binario generado
cumple los requerimientos del sector de arranque (el origen está en `0x7c00`, 
y terminamos con la *secuencia mágica* 0x55 y 0xaa), QEMU tratará el binario
como el registro de arranque principal (*del inglés MBR*) de una imágen
de disco.

Podrás observar:

![Simple bootloader which prints only `!`](http://oi60.tinypic.com/2qbwup0.jpg)

En este ejemplo podemos ver que el código será ejecutado en modo real de
16 bits, y que empezará en la dirección de memoria `0x7c00`. Luego de iniciar, 
se llama a la interrupción [0x10](http://www.ctyme.com/intr/rb-0106.htm), que
simplemente imprime el símbolo `!`. Luego se llenan los 510 bytes restantes con
ceros, y se termina con los dos *bytes mágicos* `0xaa` y `0x55`

Con la herramienta `objdump` podrás observar el residuo
binario de esta operación:

```
nasm -f bin boot.nasm
objdump -D -b binary -mi386 -Maddr16,data16,intel boot
```

Un sector de arranque real tiene código para continuar el proceso de arranque
y una tabla de partición en vez de un montón de 0's y un signo de
exclamación :) A partir de este punto, el BIOS le cede el control al cargador
de arranque.
**NOTA**: Como se puede leer más arriba, el CPU está en modo real. En este
modo, se calcula la dirección física de memoria de la siguiente forma:

```
PhysicalAddress = Segment * 16 + Offset
```

Cómo se mencionó anteriormente, solo disponemos de [registros de propósito
general](https://es.wikipedia.org/wiki/Registro_%28hardware%29) de 16 bits, el
valor máximo de un registro de 16 bits es `0xffff`, por lo que si tomamos los
valores más grandes, el resultado será:

```python
>>> hex((0xffff * 16) + 0xffff)
'0x10ffef'
```
Donde `0x10ffef` equivale a `1MB + 64KB - 16b`i. Pero un procesador
[8086](https://es.wikipedia.org/wiki/Intel_8086_y_8088), el cuál fue el primer
procesador en usar modo real, tenía una línea de dirección de 20 bits, y
`2^20 = 1048576.0`, lo que es 1MB. Esto significa que la cantidad real
de memoria disponible es 1MB.

El mapa general del modo real es:

```
0x00000000 - 0x000003FF - Real Mode Interrupt Vector Table
0x00000400 - 0x000004FF - BIOS Data Area
0x00000500 - 0x00007BFF - Unused
0x00007C00 - 0x00007DFF - Our Bootloader
0x00007E00 - 0x0009FFFF - Unused
0x000A0000 - 0x000BFFFF - Video RAM (VRAM) Memory
0x000B0000 - 0x000B7777 - Monochrome Video Memory
0x000B8000 - 0x000BFFFF - Color Video Memory
0x000C0000 - 0x000C7FFF - Video ROM BIOS
0x000C8000 - 0x000EFFFF - BIOS Shadow Area
0x000F0000 - 0x000FFFFF - System BIOS
```

Al inicio de este artículo escribí que la primera instrucción ejecutada por
el CPU se localica en `0xFFFFFFF0`, que es mucho más largo que `0xFFFFF` (1MB),
entonces ¿Cómo puede el CPU acceder a esta dirección en modo real?. La
respuesta está en la [documentación](http://www.coreboot.org/Developer_Manual/Memory_map)
de coreboot:

```
0xFFFE_0000 - 0xFFFF_FFFF: 128 kilobyte ROM mapped into address space
```
Al comienzo de la ejecución, el BIOS no está en RAM, sino en ROM.

Bootloader
--------------------------------------------------------------------------------

There are a number of bootloaders that can boot Linux, such as [GRUB 2](https://www.gnu.org/software/grub/) and [syslinux](http://www.syslinux.org/wiki/index.php/The_Syslinux_Project). The Linux kernel has a [Boot protocol](https://github.com/torvalds/linux/blob/master/Documentation/x86/boot.txt) which specifies the requirements for bootloaders to implement Linux support. This example will describe GRUB 2.

Now that the BIOS has chosen a boot device and transferred control to the boot sector code, execution starts from [boot.img](http://git.savannah.gnu.org/gitweb/?p=grub.git;a=blob;f=grub-core/boot/i386/pc/boot.S;hb=HEAD). This code is very simple due to the limited amount of space available, and contains a pointer that it uses to jump to the location of GRUB 2's core image. The core image begins with [diskboot.img](http://git.savannah.gnu.org/gitweb/?p=grub.git;a=blob;f=grub-core/boot/i386/pc/diskboot.S;hb=HEAD), which is usually stored immediately after the first sector in the unused space before the first partition. The above code loads the rest of the core image into memory, which contains GRUB 2's kernel and drivers for handling filesystems. After loading the rest of the core image, it executes [grub_main](http://git.savannah.gnu.org/gitweb/?p=grub.git;a=blob;f=grub-core/kern/main.c).

`grub_main` initializes the console, gets the base address for modules, sets the root device, loads/parses the grub configuration file, loads modules etc. At the end of execution, `grub_main` moves grub to normal mode. `grub_normal_execute` (from `grub-core/normal/main.c`) completes the last preparation and shows a menu to select an operating system. When we select one of the grub menu entries, `grub_menu_execute_entry` runs, which executes the grub `boot` command, booting the selected operating system.

As we can read in the kernel boot protocol, the bootloader must read and fill some fields of the kernel setup header, which starts at `0x01f1` offset from the kernel setup code. The kernel header [arch/x86/boot/header.S](https://github.com/torvalds/linux/blob/master/arch/x86/boot/header.S) starts from:

```assembly
	.globl hdr
hdr:
	setup_sects: .byte 0
	root_flags:  .word ROOT_RDONLY
	syssize:     .long 0
	ram_size:    .word 0
	vid_mode:    .word SVGA_MODE
	root_dev:    .word 0
	boot_flag:   .word 0xAA55
```

The bootloader must fill this and the rest of the headers (only marked as `write` in the Linux boot protocol, for example [this](https://github.com/torvalds/linux/blob/master/Documentation/x86/boot.txt#L354)) with values which it either got from command line or calculated. We will not see a description and explanation of all fields of the kernel setup header, we will get back to that when the kernel uses them. You can find a description of all fields in the [boot protocol](https://github.com/torvalds/linux/blob/master/Documentation/x86/boot.txt#L156).

As we can see in the kernel boot protocol, the memory map will be the following after loading the kernel:

```shell
         | Protected-mode kernel  |
100000   +------------------------+
         | I/O memory hole        |
0A0000   +------------------------+
         | Reserved for BIOS      | Leave as much as possible unused
         ~                        ~
         | Command line           | (Can also be below the X+10000 mark)
X+10000  +------------------------+
         | Stack/heap             | For use by the kernel real-mode code.
X+08000  +------------------------+
         | Kernel setup           | The kernel real-mode code.
         | Kernel boot sector     | The kernel legacy boot sector.
       X +------------------------+
         | Boot loader            | <- Boot sector entry point 0x7C00
001000   +------------------------+
         | Reserved for MBR/BIOS  |
000800   +------------------------+
         | Typically used by MBR  |
000600   +------------------------+
         | BIOS use only          |
000000   +------------------------+

```

So when the bootloader transfers control to the kernel, it starts at:

```
0x1000 + X + sizeof(KernelBootSector) + 1
```

where `X` is the address of the kernel bootsector loaded. In my case `X` is `0x10000`, as we can see in a memory dump:

![kernel first address](http://oi57.tinypic.com/16bkco2.jpg)

The bootloader has now loaded the Linux kernel into memory, filled the header fields and jumped to it. Now we can move directly to the kernel setup code.

Start of Kernel Setup
--------------------------------------------------------------------------------

Finally we are in the kernel. Technically the kernel hasn't run yet, we need to set up the kernel, memory manager, process manager etc first. Kernel setup execution starts from [arch/x86/boot/header.S](https://github.com/torvalds/linux/blob/master/arch/x86/boot/header.S) at [_start](https://github.com/torvalds/linux/blob/master/arch/x86/boot/header.S#L293). It is a little strange at first sight, as there are several instructions before it.

A Long time ago the Linux kernel had its own bootloader, but now if you run for example:

```
qemu-system-x86_64 vmlinuz-3.18-generic
```

You will see:

![Try vmlinuz in qemu](http://oi60.tinypic.com/r02xkz.jpg)

Actually `header.S` starts from [MZ](https://en.wikipedia.org/wiki/DOS_MZ_executable) (see image above), error message printing and following [PE](https://en.wikipedia.org/wiki/Portable_Executable) header:

```assembly
#ifdef CONFIG_EFI_STUB
# "MZ", MS-DOS header
.byte 0x4d
.byte 0x5a
#endif
...
...
...
pe_header:
	.ascii "PE"
	.word 0
```

It needs this to load an operating system with [UEFI](https://en.wikipedia.org/wiki/Unified_Extensible_Firmware_Interface). We won't see how this works right now, we'll see this in one of the next chapters.

So the actual kernel setup entry point is:

```
// header.S line 292
.globl _start
_start:
```

The bootloader (grub2 and others) knows about this point (`0x200` offset from `MZ`) and makes a jump directly to this point, despite the fact that `header.S` starts from `.bstext` section which prints an error message:

```
//
// arch/x86/boot/setup.ld
//
. = 0;                    // current position
.bstext : { *(.bstext) }  // put .bstext section to position 0
.bsdata : { *(.bsdata) }
```

So the kernel setup entry point is:

```assembly
	.globl _start
_start:
	.byte 0xeb
	.byte start_of_setup-1f
1:
	//
	// rest of the header
	//
```

Here we can see a `jmp` instruction opcode - `0xeb` to the `start_of_setup-1f` point. `Nf` notation means `2f` refers to the next local `2:` label. In our case it is label `1` which goes right after jump. It contains the rest of the setup [header](https://github.com/torvalds/linux/blob/master/Documentation/x86/boot.txt#L156). Right after the setup header we see the `.entrytext` section which starts at the `start_of_setup` label.

Actually this is the first code that runs (aside from the previous jump instruction of course). After the kernel setup got the control from the bootloader, the first `jmp` instruction is located at `0x200` (first 512 bytes) offset from the start of the kernel real mode. This we can read in the Linux kernel boot protocol and also see in the grub2 source code:

```C
  state.gs = state.fs = state.es = state.ds = state.ss = segment;
  state.cs = segment + 0x20;
```

It means that segment registers will have following values after kernel setup starts:

```
fs = es = ds = ss = 0x1000
cs = 0x1020
```

in my case when the kernel is loaded at `0x10000`.

After the jump to `start_of_setup`, it needs to do the following:

* Be sure that all values of all segment registers are equal
* Setup correct stack if needed
* Setup [bss](https://en.wikipedia.org/wiki/.bss)
* Jump to C code at [main.c](https://github.com/torvalds/linux/blob/master/arch/x86/boot/main.c)

Let's look at the implementation.

Segment registers align
--------------------------------------------------------------------------------

First of all it ensures that `ds` and `es` segment registers point to the same address and disables interrupts with `cli` instruction:

```assembly
	movw	%ds, %ax
	movw	%ax, %es
	cli	
```

As I wrote earlier, grub2 loads kernel setup code at address `0x10000` and `cs` at `0x1020` because execution doesn't start from the start of file, but from:

```
_start:
	.byte 0xeb
	.byte start_of_setup-1f
```

`jump`, which is at 512 bytes offset from the [4d 5a](https://github.com/torvalds/linux/blob/master/arch/x86/boot/header.S#L47). It also needs to align `cs` from `0x10200` to `0x10000` as all other segment registers. After that we set up the stack:

```assembly
	pushw	%ds
	pushw	$6f
	lretw
```

push `ds` value to stack, and address of [6](https://github.com/torvalds/linux/blob/master/arch/x86/boot/header.S#L494) label and execute `lretw` instruction. When we call `lretw`, it loads address of label `6` into the [instruction pointer](https://en.wikipedia.org/wiki/Program_counter) register and `cs` with value of `ds`. After this we will have `ds` and `cs` with the same values.

Stack Setup
--------------------------------------------------------------------------------

Actually, almost all of the setup code is preparation for the C language environment in real mode. The next [step](https://github.com/torvalds/linux/blob/master/arch/x86/boot/header.S#L467) is checking of `ss` register value and make a correct stack if `ss` is wrong:

```assembly
	movw	%ss, %dx
	cmpw	%ax, %dx
	movw	%sp, %dx
	je	2f
```

This can lead to 3 different scenarios:

* `ss` has valid value 0x10000 (as all other segment registers beside `cs`)
* `ss` is invalid and `CAN_USE_HEAP` flag is set     (see below)
* `ss` is invalid and `CAN_USE_HEAP` flag is not set (see below)

Let's look at all three of these scenarios:

1. `ss` has a correct address (0x10000). In this case we go to label [2](https://github.com/torvalds/linux/blob/master/arch/x86/boot/header.S#L481):

```
2: 	andw	$~3, %dx
	jnz	3f
	movw	$0xfffc, %dx
3:  movw	%ax, %ss
	movzwl %dx, %esp
	sti
```

Here we can see aligning of `dx` (contains `sp` given by bootloader) to 4 bytes and checking wether it is zero. If it is zero, we put `0xfffc` (4 byte aligned address before maximum segment size - 64 KB) in `dx`. If it is not zero we continue to use `sp` given by the bootloader (0xf7f4 in my case). After this we put the `ax` value to `ss` which stores the correct segment address of `0x10000` and sets up a correct `sp`. We now have a correct stack:

![stack](http://oi58.tinypic.com/16iwcis.jpg)

2. In the second scenario, (`ss` != `ds`). First of all put the [_end](https://github.com/torvalds/linux/blob/master/arch/x86/boot/setup.ld#L52) (address of end of setup code) value in `dx` and check the `loadflags` header field with the `testb` instruction too see wether we can use heap or not. [loadflags](https://github.com/torvalds/linux/blob/master/arch/x86/boot/header.S#L321) is a bitmask header which is defined as:

```C
#define LOADED_HIGH	    (1<<0)
#define QUIET_FLAG	    (1<<5)
#define KEEP_SEGMENTS	(1<<6)
#define CAN_USE_HEAP	(1<<7)
```

And as we can read in the boot protocol:

```
Field name:	loadflags

  This field is a bitmask.

  Bit 7 (write): CAN_USE_HEAP
	Set this bit to 1 to indicate that the value entered in the
	heap_end_ptr is valid.  If this field is clear, some setup code
	functionality will be disabled.
```

If the `CAN_USE_HEAP` bit is set, put `heap_end_ptr` in `dx` which points to `_end` and add `STACK_SIZE` (minimal stack size - 512 bytes) to it. After this if `dx` is not carry (it will not be carry, dx = _end + 512), jump to label `2` as in the previous case and make a correct stack.

![stack](http://oi62.tinypic.com/dr7b5w.jpg)

3. When `CAN_USE_HEAP` is not set, we just use a minimal stack from `_end` to `_end + STACK_SIZE`:

![minimal stack](http://oi60.tinypic.com/28w051y.jpg)

BSS Setup
--------------------------------------------------------------------------------

The last two steps that need to happen before we can jump to the main C code, are setting up the [BSS](https://en.wikipedia.org/wiki/.bss) area and checking the "magic" signature. First, signature checking:

```assembly
cmpl	$0x5a5aaa55, setup_sig
jne	setup_bad
```

This simply compares the [setup_sig](https://github.com/torvalds/linux/blob/master/arch/x86/boot/setup.ld#L39) with the magic number `0x5a5aaa55`. If they are not equal, a fatal error is reported.

If the magic number matches, knowing we have a set of correct segment registers and a stack, we only need to set up the BSS section before jumping into the C code.

The BSS section is used to store statically allocated, uninitialized data. Linux carefully ensures this area of memory is first blanked, using the following code:

```assembly
	movw	$__bss_start, %di
	movw	$_end+3, %cx
	xorl	%eax, %eax
	subw	%di, %cx
	shrw	$2, %cx
	rep; stosl
```

First of all the [__bss_start](https://github.com/torvalds/linux/blob/master/arch/x86/boot/setup.ld#L47) address is moved into `di` and the `_end + 3` address (+3 - aligns to 4 bytes) is moved into `cx`. The `eax` register is cleared (using an `xor` instruction), and the bss section size (`cx`-`di`) is calculated and put into `cx`. Then, `cx` is divided by four (the size of a 'word'), and the `stosl` instruction is repeatedly used, storing the value of `eax` (zero) into the address pointed to by `di`, automatically increasing `di` by four (this occurs until `cx` reaches zero). The net effect of this code is that zeros are written through all words in memory from `__bss_start` to `_end`:

![bss](http://oi59.tinypic.com/29m2eyr.jpg)

Jump to main
--------------------------------------------------------------------------------

That's all, we have the stack, BSS so we can jump to the `main()` C function:

```assembly
	calll main
```

The `main()` function is located in [arch/x86/boot/main.c](https://github.com/torvalds/linux/blob/master/arch/x86/boot/main.c). What this does, you can read in the next part.

Conclusion
--------------------------------------------------------------------------------

This is the end of the first part about Linux kernel internals. If you have questions or suggestions, ping me in twitter [0xAX](https://twitter.com/0xAX), drop me [email](anotherworldofworld@gmail.com) or just create [issue](https://github.com/0xAX/linux-internals/issues/new). In the next part we will see first C code which executes in Linux kernel setup, implementation of memory routines as `memset`, `memcpy`, `earlyprintk` implementation and early console initialization and many more.

**Please note that English is not my first language and I am really sorry for any inconvenience. If you found any mistakes please send me PR to [linux-internals](https://github.com/0xAX/linux-internals).**

Links
--------------------------------------------------------------------------------

  * [Intel 80386 programmer's reference manual 1986](http://css.csail.mit.edu/6.858/2014/readings/i386.pdf)
  * [Minimal Boot Loader for Intel® Architecture](https://www.cs.cmu.edu/~410/doc/minimal_boot.pdf)
  * [8086](http://en.wikipedia.org/wiki/Intel_8086)
  * [80386](http://en.wikipedia.org/wiki/Intel_80386)
  * [Reset vector](http://en.wikipedia.org/wiki/Reset_vector)
  * [Real mode](http://en.wikipedia.org/wiki/Real_mode)
  * [Linux kernel boot protocol](https://www.kernel.org/doc/Documentation/x86/boot.txt)
  * [CoreBoot developer manual](http://www.coreboot.org/Developer_Manual)
  * [Ralf Brown's Interrupt List](http://www.ctyme.com/intr/int.htm)
  * [Power supply](http://en.wikipedia.org/wiki/Power_supply)
  * [Power good signal](http://en.wikipedia.org/wiki/Power_good_signal)
