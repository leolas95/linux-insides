Proceso de arranque del kernel. Parte 4.
================================================================================

Transición al modo de 64 bits
--------------------------------------------------------------------------------

Esta es la cuarta parte de la serie `Proceso de arranque del kernel`, en donde veremos los primeros pasos en el [modo protegido](https://es.wikipedia.org/wiki/Modo_protegido), como verificar que el cpu soporte el [modo largo](https://es.wikipedia.org/wiki/Modo_largo) y las extensiones [SSE](http://en.wikipedia.org/wiki/Streaming_SIMD_Extensions), [paginación de memoria](https://es.wikipedia.org/wiki/Paginaci%C3%B3n_de_memoria) y que inicialice la tabla de páginas. Al final hablaremos acerca de la tansición al modo largo.

**NOTA: en esta sección habrá bastante código ensamblador, así que si no estás muy familiarizado con este, te recomiendo que primero leas un poco acerca de él *

En la [parte previa](https://github.com/leolas95/linux-insides-spanish/blob/master/Arranque/linux-bootstrap-3.md) nos detuvimos en el salto al punto de entrada de 32 bits, en el archivo [arch/x86/boot/pmjump.S](https://github.com/torvalds/linux/blob/master/arch/x86/boot/pmjump.S):

```assembly
jmpl	*%eax
```

Seguro recordarás que el registro `eax` contiene la dirección del punto de entrada de 32 bits. Podemos leer un poco más acerca de él en [el protocolo de arranque del kernel linux]([linux kernel x86 boot protocol](https://www.kernel.org/doc/Documentation/x86/boot.txt):

```
When using bzImage, the protected-mode kernel was relocated to 0x100000
```

Aseguremonos de que esto sea cierto echando un vistazo al valor de los registros en el punto de entrada de 32 bits:


```
eax            0x100000	1048576
ecx            0x0	    0
edx            0x0	    0
ebx            0x0	    0
esp            0x1ff5c	0x1ff5c
ebp            0x0	    0x0
esi            0x14470	83056
edi            0x0	    0
eip            0x100000	0x100000
eflags         0x46	    [ PF ZF ]
cs             0x10	16
ss             0x18	24
ds             0x18	24
es             0x18	24
fs             0x18	24
gs             0x18	24
```

Podemos ver que el registro `cs` contiene el valor `0x10` (como recordarás de la [parte anterior](https://github.com/leolas95/linux-insides-spanish/blob/master/Arranque/linux-bootstrap-3.md), este es el segundo índice en la GDT (Tabla Global de Descriptores)), el registro `eip` contiene el valor `0x100000`, y la dirección base de todos los segmentos (incluido el segmento de código) es cero. Entonces, podemos obtener la dirección física, que será `0:0x100000`, o simplemente `0x100000`, según lo especificado por el protocolo de arranque mencionado anteriormente. Ahora sí empecemos con el punto de entrada de 32 bits.

We can see here that `cs` register contains - `0x10` (as you will remember from the previous part, this is the second index in the Global Descriptor Table), `eip` register is `0x100000` and base address of all segments including the code segment are zero. So we can get the physical address, it will be `0:0x100000` or just `0x100000`, as specified by the boot protocol. Now let's start with the 32-bit entry point.

Punto de entrada de 32 bits
--------------------------------------------------------------------------------

Podemos encontrar la definición del punto de entrada de 32 bits en el archivo [arch/x86/boot/compressed/head_64.S](https://github.com/torvalds/linux/blob/master/arch/x86/boot/compressed/head_64.S):


```assembly
	__HEAD
	.code32
ENTRY(startup_32)
....
....
....
ENDPROC(startup_32)
```

Antes que nada, ¿por qué el directorio donde está el archivo se llama `compressed`? Resulta que `bzimage` es en realidad una versión comprimida usando la herramienta gzip de `vmlinux + header + código de preparación del kernel`. Ya vimos el código de preparación del kernel en las partes anteriores.

El objetivo principal de `head_64.S` es preparar todo para entrar en el modo largo, entrar en él y luego descomprimir el kernel. En esta parte veremos todos los pasos, hasta la descompresión del kernel, que veremos en la siguiente entrada.

En el directorio `arch/x86/boot/compressed` podrás ver dos archivos:

* [head_32.S](https://github.com/torvalds/linux/blob/master/arch/x86/boot/compressed/head_32.S)
* [head_64.S](https://github.com/torvalds/linux/blob/master/arch/x86/boot/compressed/head_64.S)

como este libro trata solo de la arquitectura `x86_64`, trabajaremos solamente con `head_64.S`. Echemos un vistazo a [arch/x86/boot/compressed/Makefile](https://github.com/torvalds/linux/blob/master/arch/x86/boot/compressed/Makefile). Allí podremos observar el siguiente _target_:

```Makefile
vmlinux-objs-y := $(obj)/vmlinux.lds $(obj)/head_$(BITS).o $(obj)/misc.o \
	$(obj)/string.o $(obj)/cmdline.o \
	$(obj)/piggy.o $(obj)/cpuflags.o
```

Fíjate en `$(obj)/head_$(BITS).o`. Esto significa que seleccionaremos qué archivo enlazar basados en el valor de la variable `BITS` (que será 32 o 64). Esta variable está definida en el archivo [arch/x86/Makefile](https://github.com/torvalds/linux/blob/master/arch/x86/Makefile) basada en la configuración del kernel:

```Makefile
ifeq ($(CONFIG_X86_32),y)
        BITS := 32
        ...
        ...
else
        BITS := 64
        ...
        ...
endif
```

El efecto es qué dependiendo de la variable `BITS`, que puede ser 32 o 64, enlazaremos el archivo `head_32.o` o `head_64.o`, respectivamente.

Ahora que sabemos por dónde empezar, vamos a ello.

Si hace falta, volver a cargar los segmentos
--------------------------------------------------------------------------------

Como se mencionó arriba, comenzaremos examinando el archivo [arch/x86/boot/compressed/head_64.S](https://github.com/torvalds/linux/blob/master/arch/x86/boot/compressed/head_64.S). Lo primero que vemos es la definición de la sección especial, justo antes de la definición de `startup_32`:

```assembly
    __HEAD
	.code32
ENTRY(startup_32)
```

La macro `__HEAD` está definida en el archivo de cabecera [include/linux/init.h](https://github.com/torvalds/linux/blob/master/include/linux/init.h), y se expande en lo siguiente:

```C
#define __HEAD		.section	".head.text","ax"
```

siendo `.head.text` el nombre y `ax` banderas. En nuestro caso, estas banderas nos indican que está sección (texto) es [ejecutable](https://es.wikipedia.org/wiki/Ejecutable), es decir, que contiene código. Podemos ver la definición de esta sección en el guión del enlazador [arch/x86/boot/compressed/vmlinux.lds.S](https://github.com/torvalds/linux/blob/master/arch/x86/boot/compressed/vmlinux.lds.S):

```
SECTIONS
{
	. = 0;
	.head.text : {
		_head = . ;
		HEAD_TEXT
		_ehead = . ;
	}
	...
```

Si no estás familiarizado con la sintaxis del enlazador `GNU LD`, puedes leer acerca de él en su [documentación](https://sourceware.org/binutils/docs/ld/Scripts.html#Scripts). En resumidas cuentas, el símbolo `.` es una variable especial del enlazador (contador de localización). El valor que se le asigne es un desplazamiento relativo al desplazamiento del segmento. En nuestro caso le asignamos cero al contador de localización. Esto significa que nuestro código es enlazado para comenzar a ejecutarse desde el desplazamiento `0` en la memoria. Por otra parte, también podemos encontrar el siguiente comentario.

```
Be careful parts of head_64.S assume startup_32 is at address 0.
```

Ok, ahora ya sabemos donde estamos parados, y es un buen momento para mirar dentro de la función `startup_32`.

En el inicio de la función `startup_32`, podemos ver la instrucción `cld`, que limpia el bit `DF` (**D**irection **F**lag, Bandera de dirección)(https://en.wikipedia.org/wiki/Direction_flag) en el registro [FLAGS](https://es.wikipedia.org/wiki/Registro_FLAGS). Cuando la bandera de dirección está en cero, todas las operaciones sobre strings, tales como [stos](http://x86.renejeschke.de/html/file_module_x86_id_306.html) y [scas](http://x86.renejeschke.de/html/file_module_x86_id_287.html) incrementarán los registros `esi` o `edi`. Establecemos la bandera de dirección a cero porque más adelante usaremos estas operaciones sobre strings para limpiar espacio para la tabla de páginas, entre otras cosas.

Luego de que hemos limpiado el bit `DF`, el siguiente paso revisar la bandera `KEEP_SEGMENTS`, del archivo de configuración del kernel `loadflags`. Si recuerdas, ya vimos el archivo `loadflags` en la [primera parte](https://github.com/leolas95/linux-insides-spanish/blob/master/Arranque/linux-bootstrap-1.md) del libro. Allí, revisamos la bandera `CAN_USE_HEAP` para tener la habilidad de poder usar el montón. Ahora, tenemos que revisar la bandera `KEEP_SEGMENTS`. Esta bandera está descrita en la documentación del [protocolo de arranque](https://www.kernel.org/doc/Documentation/x86/boot.txt) de linux:

```
Bit 6 (write): KEEP_SEGMENTS
  Protocol: 2.07+
  - If 0, reload the segment registers in the 32bit entry point.
  - If 1, do not reload the segment registers in the 32bit entry point.
    Assume that %cs %ds %ss %es are all set to flat segments with
	a base of 0 (or the equivalent for their environment).
```

Por lo tanto, si el bit `KEEP_SEGMENTS` no está encendido, tenemos que resetear los registros de segmentos `ds`, `ss` y `es` al índice del segmento de datos, con base `0`. Para eso hacemos:

```C
	testb $(1 << 6), BP_loadflags(%esi)
	jnz 1f

	cli
	movl	$(__BOOT_DS), %eax
	movl	%eax, %ds
	movl	%eax, %es
	movl	%eax, %ss
```

Recuerda que el valor de `__BOOT_DS` es `0x18` (índice del segmento de datos en la [Tabla Global de Descriptores](https://en.wikipedia.org/wiki/Global_Descriptor_Table)). Si el bit `KEEP_SEGMENTS` está encendido, entonces saltamos a la etiqueta `1f` más cercana. Sino, actualizamos los registros de segmento con el valor de  `__BOOT_DS`. Es bastante simple, pero hay detalle interesante: si has leído la [artículo anterior](https://github.com/leolas95/linux-insides-spanish/blob/master/Arranque/linux-bootstrap-3.md), recordarás que ya habíamos actualizado el valor de estos registros de segmento justo después de haber saltado al [modo protegido](https://es.wikipedia.org/wiki/Modo_protegido) en [arch/x86/boot/pmjump.S](https://github.com/torvalds/linux/blob/master/arch/x86/boot/pmjump.S). Así que, ¿por qué debemos preocuparnos otra vez por los valores de los registros de segmento?. Bueno, la respuesta es simple. El kernel Linux también tiene un protocolo de arranque de 32 bits, y si el cargador de arranque lo usa para cargar el kernel, todo el código antes de `startup_32` será saltado (ignorado). En este caso, `startup_32` será el primer punto de entrada al kernel justo después del cargador de arranque, y no hay ninguna garantía de que los registros de segmento estén en un estado conocido.

Luego de que hemos revisado la bandera `KEEP_SEGMENTS` y colocado el valor adecuado en los registros de segmento, el siguiente paso es calcular la diferencia entre en dónde cargamos y compilamos para ejecutar(!). Recuerda que `setup.ld.S` tiene la siguiente definición: `. = 0` al inicio de la sección `.head.text`. Esto significa que el código en esta sección será compilado para ejecutarse a partir de la dirección `0`. Podemos ver esto al observar la salida del programa `objdump`:

```
arch/x86/boot/compressed/vmlinux:     file format elf64-x86-64


Disassembly of section .head.text:

0000000000000000 <startup_32>:
   0:   fc                      cld
   1:   f6 86 11 02 00 00 40    testb  $0x40,0x211(%rsi)
```

`objdump` nos dice que la dirección de `startup_32` es `0`. Pero en realidad no es así. Nuestro objetivo actual es saber dónde realmente estamos. Esto es fácil de hacer en el [modo largo](https://es.wikipedia.org/wiki/Modo_largo), porque este soporta direcciónamiento relativo con `rip`. Pero actualmente no estamos en modo largo, estamos en [modo protegido](https://es.wikipedia.org/wiki/Modo_protegido). Usaremos una técnica común para hallar la dirección de `startup_32`. Primero, tenemos que definir una etiqueta, luego hacer una llamada a esta, y luego extraer el tope de la pila (pop) de llamadas a un registro:

```assembly
call label
label: pop %reg
```

Luego de esto el registro `%reg` contendrá la dirección de la etiqueta. Echemos un vistazo al código encargado de esto en el kernel Linux:

```assembly
	leal	(BP_scratch+4)(%esi), %esp
	call	1f
1:      popl	%ebp
	subl	$1b, %ebp
```

Como recordarás de la parte anterior, el registro `esi` contiene la dirección de la [estructura *boot params*](https://github.com/torvalds/linux/blob/master/arch/x86/include/uapi/asm/bootparam.h#L152), que fue llenada antes de que nos movieramos al modo protegido. La estructura `boot_params` contiene un campo especial, `scratch` (`__u32 scratch`), desplazado `0x1e4` bytes dentro del espacio de memoria de la estructura. Este campo de 4 bytes será la pila de llamadas temporal para la instrucción `call`. En el código mostrado arriba, estamos obteniendo la dirección del campo `scratch` + 4 bytes y colocandola en el regisro `esp`. Estamos sumando 4 bytes al campo base `BP_scratch` porque, como se mencionó, `scratch` será un espacio temporal para la pila de llamadas, y en la arquitectura `x86_64` la pila crece en dirección descendente (de arriba hacia abajo, desde las direcciones más altas hacia las más bajas). Por lo que luego de ejecutada la primera instrucción, nuestro apuntador de pila apuntará al tope de la pila. Seguidamente, podemos observar el patrón descrito arriba; hacemos una llamada a la etiqueta `1f`, y colocamos la dirección de esta etiqueta en el registro `ebp`, porque luego de ejecutar la instrucción `call` la dirección de retorno está en el tope de la pila. Así que por ahora, tenemos la dirección de la etiqueta `1f` y es fácil obtener la dirección de `startup_32`. Solo tenemos que restar la dirección de la etiqueta de la dirección que obtuvimos de la pila:

```
startup_32 (0x0)     +-----------------------+
                     |                       |
                     |                       |
                     |                       |
                     |                       |
                     |                       |
                     |                       |
                     |                       |
                     |                       |
1f (0x0 + 1f offset) +-----------------------+ %ebp - real physical address
                     |                       |
                     |                       |
                     +-----------------------+
```

`startup_32` está enlazado para ejecutarse en la dirección `0x0`, y esto significa que `1f` tiene la dirección `0x0 + desplazamiento a 1f`, aproximadamente `0x21` bytes. El registro `ebp` conteiene la dirección física real de la etiqueta `1f`. Por lo tanto, si restamos `1f` de `ebp`, obtenemos la dirección física real de `startup_32`. El [protocolo de arranque](https://www.kernel.org/doc/Documentation/x86/boot.txt) del kernel Linux describe que la base del kernel de modo protegido es `0x100000`. Podemos verificarlo usando [gdb](https://en.wikipedia.org/wiki/GNU_Debugger). Iniciemos el depurador y pongamos un _breakpoint_ en la dirección `1f`, que es `0x100021`. Si lo que hicimos es correcto, deberiamos ver el valor `0x100021` en el registro `ebp`:

```
$ gdb
(gdb)$ target remote :1234
Remote debugging using :1234
0x0000fff0 in ?? ()
(gdb)$ br *0x100022
Breakpoint 1 at 0x100022
(gdb)$ c
Continuing.

Breakpoint 1, 0x00100022 in ?? ()
(gdb)$ i r
eax            0x18	0x18
ecx            0x0	0x0
edx            0x0	0x0
ebx            0x0	0x0
esp            0x144a8	0x144a8
ebp            0x100021	0x100021
esi            0x142c0	0x142c0
edi            0x0	0x0
eip            0x100022	0x100022
eflags         0x46	[ PF ZF ]
cs             0x10	0x10
ss             0x18	0x18
ds             0x18	0x18
es             0x18	0x18
fs             0x18	0x18
gs             0x18	0x18
```

Si ejecutamos la siguiente instrucción, `subl $1b, %ebp`, veremos lo siguiente:

```
nexti
...
ebp            0x100000	0x100000
...
```

Por lo que se verifican nuestras suposiciones, la dirección de `startup_32` es `0x100000`. Luego de que sepamos la dirección de la etiqueta `startup_32`, podemos prepararnos para la transición al [modo largo](https://en.wikipedia.org/wiki/Long_mode). Nuestro siguiente objetivo es preparar la pila y verificar que el CPU tenga soporte para el modo largo y [SSE](http://en.wikipedia.org/wiki/Streaming_SIMD_Extensions).

Stack setup and CPU verification
--------------------------------------------------------------------------------

We could not setup the stack while we did not know the address of the `startup_32` label. We can imagine the stack as an array and the stack pointer register `esp` must point to the end of this array. Of course we can define an array in our code, but we need to know its actual address to configure the stack pointer in a correct way. Let's look at the code:

```assembly
	movl	$boot_stack_end, %eax
	addl	%ebp, %eax
	movl	%eax, %esp
```

The `boot_stack_end` label, defined in the same [arch/x86/boot/compressed/head_64.S](https://github.com/torvalds/linux/blob/master/arch/x86/boot/compressed/head_64.S) assembly source code file and located in the [.bss](https://en.wikipedia.org/wiki/.bss) section:

```assembly
	.bss
	.balign 4
boot_heap:
	.fill BOOT_HEAP_SIZE, 1, 0
boot_stack:
	.fill BOOT_STACK_SIZE, 1, 0
boot_stack_end:
```

First of all, we put the address of `boot_stack_end` into the `eax` register, so the `eax` register contains the address of `boot_stack_end` where it was linked, which is `0x0 + boot_stack_end`. To get the real address of `boot_stack_end`, we need to add the real address of the `startup_32`. As you remember, we have found this address above and put it to the `ebp` register. In the end, the register `eax` will contain real address of the `boot_stack_end` and we just need to put to the stack pointer.

After we have set up the stack, next step is CPU verification. As we are going to execute transition to the `long mode`, we need to check that the CPU supports `long mode` and `SSE`. We will do it by the call of the `verify_cpu` function:

```assembly
	call	verify_cpu
	testl	%eax, %eax
	jnz	no_longmode
```

This function defined in the [arch/x86/kernel/verify_cpu.S](https://github.com/torvalds/linux/blob/master/arch/x86/kernel/verify_cpu.S) assembly file and just contains a couple of calls to the [cpuid](https://en.wikipedia.org/wiki/CPUID) instruction. This instruction is used for getting information about the processor. In our case it checks `long mode` and `SSE` support and returns `0` on success or `1` on fail in the `eax` register.

If the value of the `eax` is not zero, we jump to the `no_longmode` label which just stops the CPU by the call of the `hlt` instruction while no hardware interrupt will not happen:

```assembly
no_longmode:
1:
	hlt
	jmp     1b
```

If the value of the `eax` register is zero, everything is ok and we are able to continue.

Calculate relocation address
--------------------------------------------------------------------------------

The next step is calculating relocation address for decompression if needed. First we need to know what it means for a kernel to be `relocatable`. We already know that the base address of the 32-bit entry point of the Linux kernel is `0x100000`, but that is a 32-bit entry point. The default base address of the Linux kernel is determined by the value of the `CONFIG_PHYSICAL_START` kernel configuration option. Its default value is `0x1000000` or `1 MB`. The main problem here is that if the Linux kernel crashes, a kernel developer must have a `rescue kernel` for [kdump](https://www.kernel.org/doc/Documentation/kdump/kdump.txt) which is configured to load from a different address. The Linux kernel provides special configuration option to solve this problem: `CONFIG_RELOCATABLE`. As we can read in the documentation of the Linux kernel:

```
This builds a kernel image that retains relocation information
so it can be loaded someplace besides the default 1MB.

Note: If CONFIG_RELOCATABLE=y, then the kernel runs from the address
it has been loaded at and the compile time physical address
(CONFIG_PHYSICAL_START) is used as the minimum location.
```

In simple terms this means that the Linux kernel with the same configuration can be booted from different addresses. Technically, this is done by compiling the decompressor as [position independent code](https://en.wikipedia.org/wiki/Position-independent_code). If we look at [arch/x86/boot/compressed/Makefile](https://github.com/torvalds/linux/blob/master/arch/x86/boot/compressed/Makefile), we will see that the decompressor is indeed compiled with the `-fPIC` flag:

```Makefile
KBUILD_CFLAGS += -fno-strict-aliasing -fPIC
```

When we are using position-independent code an address is obtained by adding the address field of the command and the value of the program counter. We can load code which uses such addressing from any address. That's why we had to get the real physical address of `startup_32`. Now let's get back to the Linux kernel code. Our current goal is to calculate an address where we can relocate the kernel for decompression. Calculation of this address depends on `CONFIG_RELOCATABLE` kernel configuration option. Let's look at the code:

```assembly
#ifdef CONFIG_RELOCATABLE
	movl	%ebp, %ebx
	movl	BP_kernel_alignment(%esi), %eax
	decl	%eax
	addl	%eax, %ebx
	notl	%eax
	andl	%eax, %ebx
	cmpl	$LOAD_PHYSICAL_ADDR, %ebx
	jge	1f
#endif
	movl	$LOAD_PHYSICAL_ADDR, %ebx
1:
	addl	$z_extract_offset, %ebx
```

Remember that the value of the `ebp` register is the physical address of the `startup_32` label. If the `CONFIG_RELOCATABLE` kernel configuration option is enabled during kernel configuration, we put this address in the `ebx` register, align it to a multiple of `2MB` and compare it with the `LOAD_PHYSICAL_ADDR` value. The `LOAD_PHYSICAL_ADDR` macro is defined in the [arch/x86/include/asm/boot.h](https://github.com/torvalds/linux/blob/master/arch/x86/include/asm/boot.h) header file and it looks like this:

```C
#define LOAD_PHYSICAL_ADDR ((CONFIG_PHYSICAL_START \
				+ (CONFIG_PHYSICAL_ALIGN - 1)) \
				& ~(CONFIG_PHYSICAL_ALIGN - 1))
```

As we can see it just expands to the aligned `CONFIG_PHYSICAL_ALIGN` value which represents the physical address of where to load the kernel. After comparison of the `LOAD_PHYSICAL_ADDR` and value of the `ebx` register, we add the offset from the `startup_32` where to decompress the compressed kernel image. If the `CONFIG_RELOCATABLE` option is not enabled during kernel configuration, we just put the default address where to load kernel and add `z_extract_offset` to it.

After all of these calculations we will have `ebp` which contains the address where we loaded it and `ebx` set to the address of where kernel will be moved after decompression.

Preparation before entering long mode
--------------------------------------------------------------------------------

When we have the base address where we will relocate the compressed kernel image, we need to do one last step before we can transition to 64-bit mode. First we need to update the [Global Descriptor Table](https://en.wikipedia.org/wiki/Global_Descriptor_Table):

```assembly
	leal	gdt(%ebp), %eax
	movl	%eax, gdt+2(%ebp)
	lgdt	gdt(%ebp)
```

Here we put the base address from `ebp` register with `gdt` offset into the `eax` register. Next we put this address into `ebp` register with offset `gdt+2` and load the `Global Descriptor Table` with the `lgdt` instruction. To understand the magic with `gdt` offsets we need to look at the definition of the `Global Descriptor Table`. We can find its definition in the same source code [file](https://github.com/torvalds/linux/blob/master/arch/x86/boot/compressed/head_64.S):

```assembly
	.data
gdt:
	.word	gdt_end - gdt
	.long	gdt
	.word	0
	.quad	0x0000000000000000	/* NULL descriptor */
	.quad	0x00af9a000000ffff	/* __KERNEL_CS */
	.quad	0x00cf92000000ffff	/* __KERNEL_DS */
	.quad	0x0080890000000000	/* TS descriptor */
	.quad   0x0000000000000000	/* TS continued */
gdt_end:
```

We can see that it is located in the `.data` section and contains five descriptors: `null` descriptor, kernel code segment, kernel data segment and two task descriptors. We already loaded the `Global Descriptor Table` in the previous [part](https://github.com/0xAX/linux-insides/blob/master/Booting/linux-bootstrap-3.md), and now we're doing almost the same here, but descriptors with `CS.L = 1` and `CS.D = 0` for execution in `64` bit mode. As we can see, the definition of the `gdt` starts from two bytes: `gdt_end - gdt` which represents last byte in the `gdt` table or table limit. The next four bytes contains base address of the `gdt`. Remember that the `Global Descriptor Table` is stored in the `48-bits GDTR` which consists of two parts:

* size(16-bit) of global descriptor table;
* address(32-bit) of the global descriptor table.

So, we put address of the `gdt` to the `eax` register and then we put it to the `.long	gdt` or `gdt+2` in our assembly code. From now we have formed structure for the `GDTR` register and can load the `Global Descriptor Table` with the `lgtd` instruction.

After we have loaded the `Global Descriptor Table`, we must enable [PAE](http://en.wikipedia.org/wiki/Physical_Address_Extension) mode by putting the value of the `cr4` register into `eax`, setting 5 bit in it and loading it again into `cr4`:

```assembly
	movl	%cr4, %eax
	orl	$X86_CR4_PAE, %eax
	movl	%eax, %cr4
```

Now we are almost finished with all preparations before we can move into 64-bit mode. The last step is to build page tables, but before that, here is some information about long mode.

Long mode
--------------------------------------------------------------------------------

[Long mode](https://en.wikipedia.org/wiki/Long_mode) is the native mode for [x86_64](https://en.wikipedia.org/wiki/X86-64) processors. First let's look at some differences between `x86_64` and the `x86`.

The `64-bit` mode provides features such as:

* New 8 general purpose registers from `r8` to `r15` + all general purpose registers are 64-bit now;
* 64-bit instruction pointer - `RIP`;
* New operating mode - Long mode;
* 64-Bit Addresses and Operands;
* RIP Relative Addressing (we will see an example of it in the next parts).

Long mode is an extension of legacy protected mode. It consists of two sub-modes:

* 64-bit mode;
* compatibility mode.

To switch into `64-bit` mode we need to do following things:

* Enable [PAE](https://en.wikipedia.org/wiki/Physical_Address_Extension);
* Build page tables and load the address of the top level page table into the `cr3` register;
* Enable `EFER.LME`;
* Enable paging.

We already enabled `PAE` by setting the `PAE` bit in the `cr4` control register. Our next goal is to build the structure for [paging](https://en.wikipedia.org/wiki/Paging). We will see this in next paragraph.

Early page table initialization
--------------------------------------------------------------------------------

So, we already know that before we can move into `64-bit` mode, we need to build page tables, so, let's look at the building of early `4G` boot page tables.

**NOTE: I will not describe the theory of virtual memory here. If you need to know more about it, see links at the end of this part.**

The Linux kernel uses `4-level` paging, and we generally build 6 page tables:

* One `PML4` or `Page Map Level 4` table with one entry;
* One `PDP` or `Page Directory Pointer` table with four entries;
* Four Page Directory tables with a total of `2048` entries.

Let's look at the implementation of this. First of all we clear the buffer for the page tables in memory. Every table is `4096` bytes, so we need clear `24` kilobyte buffer:

```assembly
	leal	pgtable(%ebx), %edi
	xorl	%eax, %eax
	movl	$((4096*6)/4), %ecx
	rep	stosl
```

We put the address of `pgtable` plus `ebx` (remember that `ebx` contains the address to relocate the kernel for decompression) in the `edi` register, clear the `eax` register and set the `ecx` register to `6144`. The `rep stosl` instruction will write the value of the `eax` to `edi`, increase value of the `edi` register by `4` and decrease the value of the `ecx` register by `1`. This operation will be repeated while the value of the `ecx` register is greater than zero. That's why we put `6144` in `ecx`.

`pgtable` is defined at the end of [arch/x86/boot/compressed/head_64.S](https://github.com/torvalds/linux/blob/master/arch/x86/boot/compressed/head_64.S) assembly file and is:

```assembly
	.section ".pgtable","a",@nobits
	.balign 4096
pgtable:
	.fill 6*4096, 1, 0
```

As we can see, it is located in the `.pgtable` section and its size is `24` kilobytes.

After we have got buffer for the `pgtable` structure, we can start to build the top level page table - `PML4` - with:

```assembly
	leal	pgtable + 0(%ebx), %edi
	leal	0x1007 (%edi), %eax
	movl	%eax, 0(%edi)
```

Here again, we put the address of the `pgtable` relative to `ebx` or in other words relative to address of the `startup_32` to the `edi` register. Next we put this address with offset `0x1007` in the `eax` register. The `0x1007` is `4096` bytes which is the size of the `PML4` plus `7`. The `7` here represents flags of the `PML4` entry. In our case, these flags are `PRESENT+RW+USER`. In the end we just write first the address of the first `PDP` entry to the `PML4`.

In the next step we will build four `Page Directory` entries in the `Page Directory Pointer` table with the same `PRESENT+RW+USE` flags:

```assembly
	leal	pgtable + 0x1000(%ebx), %edi
	leal	0x1007(%edi), %eax
	movl	$4, %ecx
1:  movl	%eax, 0x00(%edi)
	addl	$0x00001000, %eax
	addl	$8, %edi
	decl	%ecx
	jnz	1b
```

We put the base address of the page directory pointer which is `4096` or `0x1000` offset from the `pgtable` table in `edi` and the address of the first page directory pointer entry in `eax` register. Put `4` in the `ecx` register, it will be a counter in the following loop and write the address of the first page directory pointer table entry to the `edi` register. After this `edi` will contain the address of the first page directory pointer entry with flags `0x7`. Next we just calculate the address of following page directory pointer entries where each entry is `8` bytes, and write their addresses to `eax`. The last step of building paging structure is the building of the `2048` page table entries with `2-MByte` pages:

```assembly
	leal	pgtable + 0x2000(%ebx), %edi
	movl	$0x00000183, %eax
	movl	$2048, %ecx
1:  movl	%eax, 0(%edi)
	addl	$0x00200000, %eax
	addl	$8, %edi
	decl	%ecx
	jnz	1b
```

Here we do almost the same as in the previous example, all entries will be with flags - `$0x00000183` - `PRESENT + WRITE + MBZ`. In the end we will have `2048` pages with `2-MByte` page or:

```python
>>> 2048 * 0x00200000
4294967296
```

`4G` page table. We just finished to build our early page table structure which maps `4` gigabytes of memory and now we can put the address of the high-level page table - `PML4` - in `cr3` control register:

```assembly
	leal	pgtable(%ebx), %eax
	movl	%eax, %cr3
```

That's all. All preparation are finished and now we can see transition to the long mode.

Transition to the 64-bit mode
--------------------------------------------------------------------------------

First of all we need to set the `EFER.LME` flag in the [MSR](http://en.wikipedia.org/wiki/Model-specific_register) to `0xC0000080`:

```assembly
	movl	$MSR_EFER, %ecx
	rdmsr
	btsl	$_EFER_LME, %eax
	wrmsr
```

Here we put the `MSR_EFER` flag (which is defined in [arch/x86/include/uapi/asm/msr-index.h](https://github.com/torvalds/linux/blob/master/arch/x86/include/uapi/asm/msr-index.h#L7)) in the `ecx` register and call `rdmsr` instruction which reads the [MSR](http://en.wikipedia.org/wiki/Model-specific_register) register. After `rdmsr` executes, we will have the resulting data in `edx:eax` which depends on the `ecx` value. We check the `EFER_LME` bit with the `btsl` instruction and write data from `eax` to the `MSR` register with the `wrmsr` instruction.

In the next step we push the address of the kernel segment code to the stack (we defined it in the GDT) and put the address of the `startup_64` routine in `eax`.

```assembly
	pushl	$__KERNEL_CS
	leal	startup_64(%ebp), %eax
```

After this we push this address to the stack and enable paging by setting `PG` and `PE` bits in the `cr0` register:

```assembly
	movl	$(X86_CR0_PG | X86_CR0_PE), %eax
	movl	%eax, %cr0
```

and execute:

```assembly
lret
```

instruction. Remember that we pushed the address of the `startup_64` function to the stack in the previous step, and after the `lret` instruction, the CPU extracts the address of it and jumps there.

After all of these steps we're finally in 64-bit mode:

```assembly
	.code64
	.org 0x200
ENTRY(startup_64)
....
....
....
```

That's all!

Conclusion
--------------------------------------------------------------------------------

This is the end of the fourth part linux kernel booting process. If you have questions or suggestions, ping me in twitter [0xAX](https://twitter.com/0xAX), drop me [email](anotherworldofworld@gmail.com) or just create an [issue](https://github.com/0xAX/linux-insides/issues/new).

In the next part we will see kernel decompression and many more.

**Please note that English is not my first language and I am really sorry for any inconvenience. If you find any mistakes please send me PR to [linux-insides](https://github.com/0xAX/linux-internals).**

Links
--------------------------------------------------------------------------------

* [Protected mode](http://en.wikipedia.org/wiki/Protected_mode)
* [Intel® 64 and IA-32 Architectures Software Developer’s Manual 3A](http://www.intel.com/content/www/us/en/processors/architectures-software-developer-manuals.html)
* [GNU linker](http://www.eecs.umich.edu/courses/eecs373/readings/Linker.pdf)
* [SSE](http://en.wikipedia.org/wiki/Streaming_SIMD_Extensions)
* [Paging](http://en.wikipedia.org/wiki/Paging)
* [Model specific register](http://en.wikipedia.org/wiki/Model-specific_register)
* [.fill instruction](http://www.chemie.fu-berlin.de/chemnet/use/info/gas/gas_7.html)
* [Previous part](https://github.com/0xAX/linux-insides/blob/master/Booting/linux-bootstrap-3.md)
* [Paging on osdev.org](http://wiki.osdev.org/Paging)
* [Paging Systems](https://www.cs.rutgers.edu/~pxk/416/notes/09a-paging.html)
* [x86 Paging Tutorial](http://www.cirosantilli.com/x86-paging/)
