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
Obtenemos `0xfffffff0`, que son 4GB - 16 bytes. Este punto es llamado [Vector de reinicio](https://en.wikipedia.org/wiki/Reset_vector).
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
que acabamos de crear arriba como una imagen de disco. Como el binario generado
cumple los requerimientos del sector de arranque (el origen está en `0x7c00`, 
y terminamos con la *secuencia mágica* 0x55 y 0xaa), QEMU tratará el binario
como el registro de arranque principal (*del inglés MBR*) de una imagen
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

Cargador de arranque
--------------------------------------------------------------------------------

Existe un buen número de cargadores de arranque que funcionan con Linux,
tales como [GRUB 2](https://www.gnu.org/software/grub/)
y [syslinux](http://www.syslinux.org/wiki/index.php/The_Syslinux_Project).
El kernel Linux tiene un [protocolo de arranque](https://github.com/torvalds/linux/blob/master/Documentation/x86/boot.txt) que le indica a los
cargadores de arranque los requerimientos para soportar Linux.
El siguiente ejemplo describirá GRUB 2.

Ahora, una vez que el BIOS ha elegido un dispositivo de arranque y transferido
el control al código del sector de arranque, la ejecución comienza desde
[boot.img](http://git.savannah.gnu.org/gitweb/?p=grub.git;a=blob;f=grub-core/boot/i386/pc/boot.S;hb=HEAD).
Debido a la limitada cantidad de espacio disponible, este código es bastante
simple, y contiene un puntero utilizado para moverse a la localización de la
imagen central de GRUB 2.(!!)

La imagen central comienza con [diskboot.img](http://git.savannah.gnu.org/gitweb/?p=grub.git;a=blob;f=grub-core/boot/i386/pc/diskboot.S;hb=HEAD),
que usualmente se almacena en el primer sector del espacio disponible antes
de la primera partición. El código mostrado arriba dirige el resto de la
imagen central a la memoria, la cual el kernel y los controladores de
GRUB 2 para el manejo de sistemas de archivos. Luego de cargar el resto de
la imagen cetral, se ejecuta [grub main](http://git.savannah.gnu.org/gitweb/?p=grub.git;a=blob;f=grub-core/kern/main.c)

`grub main` inicializa la consola, obtiene la dirección básica para los
módulos, establece el dispositivo raíz, carga/analiza el archivo de
configuración de GRUB, carga los módulos, etc. Al final de la ejecución,
`grub_main` pone a grub en modo normal. `grub_normal_execute`
(en `grub-core/normal/main.c`) termina los detalles finales y luego muestra
un menú para seleccionar el sistema operativo. Cuando elegimos alguna de
las opciones, se ejecuta `grub_menu_execute_entry`, que a su vez ejecuta
el comando `boot`, iniciando así el sistema operativo.

Como podemos leer en el protocolo de arranque del kernel, el cargador de
arranque debe leer y llenar algunos campos en el archivo de cabecera de
configuración del kernel, el cual comienza a una distancia relativa
de `0x01f1` del código de configuración del kernel. El archivo
de cabecera del kernel [arch/x86/boot/header.S](https://github.com/torvalds/linux/blob/master/arch/x86/boot/header.S) inicia desde:

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
El cargador de arranque debe llenar este y otros archivos de cabecera
(solo los marcados como `write` en el protocolo de arranque de Linux,
por ejemplo [este](https://github.com/torvalds/linux/blob/master/Documentation/x86/boot.txt#L354)) con valores que, o bien se obtuvieron de la línea
de comandos, o bien se calcularon. Por ahora no ahondaremos mucho
en describir y explicar todos los campos del archivo de cabecera del
kernel; nos enfocaremos más en ellos cuando el kernel los use. Podrás
encontrar una descripción de dichos campos en el
[protocolo de arranque](https://github.com/torvalds/linux/blob/master/Documentation/x86/boot.txt#L156)

Como podemos observar en el protocolo de arranque, luego de cargar el
kernel, el mapa de la memoria será el siguiente:

```shell
         | Modo protegido del kernel |
100000   +---------------------------+
         | Hueco de memoria de E/S   |
0A0000   +---------------------------+
         | Reservado para el BIOS    | Dejar cuanto sea posible sin usar
         ~                           ~
         | Línea de comandos         | (También puede estar debajo de la marca x+10000)
X+10000  +---------------------------+
         | Pila/montón               | Usado por el código de modo real del kernel.
X+08000  +---------------------------+
         | Configuración del kernel  | El código del modo real.
         | Sector de arranque        | Sector de arranque heredado (del inglés *legacy*)
       X +---------------------------+
         | Cargador de arranque      | <- Sector de entrada de arranque en 0x7C00
001000   +---------------------------+
         | Reservado para MBR/BIOS   |
000800   +---------------------------+
         | Generalmente usado por MBR|
000600   +---------------------------+
         | Solo para uso del  BIOS   |
000000   +---------------------------+

```

Por lo tanto, cuando el cargador de arranque le transfiere el control al kernel,
este comienza en:

```
0x1000 + X + sizeof(KernelBootSector) + 1
```

Donde `X` es la dirección del sector de arranque cargado. En mi caso, `X` es
`0x10000`, como podemos observar en un volcado de memoria:

![kernel first address](http://oi57.tinypic.com/16bkco2.jpg)

En este punto, el cargador de arranque ya ha cargado el kernel en memoria, 
llenado los archivos de cabecera, y finalmente movido al kernel(!!).
Ya podemos movernos directamente al código de arranque del kernel.


Inicio de la configuración del kernel
--------------------------------------------------------------------------------

Finalmente llegamos al kernel, aunque este aún no se ha ejecutado, ya que
primero este debe configurarse, al igual que el administrador de memoria, el 
administrador de procesos, etc. La ejecucuón del kernel inicia en
[_start](https://github.com/torvalds/linux/blob/master/arch/x86/boot/header.S#L293),
ubicado en [arch/x86/boot/header.S](https://github.com/torvalds/linux/blob/master/arch/x86/boot/header.S).
Puede parecer extraño el principio, ya que antes pueden haber varias instrucciones.

Hace mucho tiempo el kernel Linux tenía su propio cargador de arranque, pero
si actualmente ejecutas, por ejemplo:

```
qemu-system-x86_64 vmlinuz-3.18-generic
```

Verás:

![Try vmlinuz in qemu](http://oi60.tinypic.com/r02xkz.jpg)

De hecho, `header.S` comienza desde [MZ](https://en.wikipedia.org/wiki/DOS_MZ_executable)
(ver imagen arriba), imprimiendo mensajes de error(!!), y el siguiente
[PE](https://en.wikipedia.org/wiki/Portable_Executable) archivo de cabecera:

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

Esto es necesario para cargar un sistema operativo con [UEFI](https://en.wikipedia.org/wiki/Unified_Extensible_Firmware_Interface).
Por ahora no veremos cómo funciona esto, sino en alguno de los siguientes capítulos.

Por lo que el verdadero pundo de entrada del kernel es:

```
// header.S line 292
.globl _start
_start:
```

El cargador de arranque (grub2 y otros) conoce acerca de este punto
(una distancia relativa de `0x200` desde `MZ`) por lo que realiza un salto
directamente a este, a pesar del heco de que `header.S` comience desde la
sección `.bstext`, que imprime un mensaje de error:

```
//
// arch/x86/boot/setup.ld
//
. = 0;                    // Posción actual
.bstext : { *(.bstext) }  // Coloca la sección .bstext en la posición 0
.bsdata : { *(.bsdata) }
```

Por lo que el punto de entrada del kernel es:

```assembly
	.globl _start
_start:
	.byte 0xeb
	.byte start_of_setup-1f
1:
	//
	// resto del archivo de cabecera
	//
```

Aquí podemos ver un código de operación a una instrucción `jmp`(!!) - desde `0xeb`
hasta el punto `start_of_setup-1f`. La notación `Nf` significa que,
por ejemplo `2f` se refiere a la siguiente etiqueta local `2:`. En nuestro caso
`1`, la cual va justo después del salto. Esta contiene el resto del
[archivo de cabecera de configuración](https://github.com/torvalds/linux/blob/master/Documentation/x86/boot.txt#L156).
Justo después de este archivo, veremos la sección `.entrytext`, la cual
comienza en la etiqueta `start_of_setup`.

De hecho, este es el primer código que se ejectua (a parte de la instrucción
de salto previa). Luego de que la configuración del kernel obtiene el control
del cargador de arranque, la primera instrucción `jmp` se localiza a una
distancia relativa de `0x200` (los primeros 512 bytes)  del inicio del
modo real del kernel. Esto lo podemos ver en el protocolo de arranque
del kernel, y también en el código fuente de grub2:


```C
  state.gs = state.fs = state.es = state.ds = state.ss = segment;
  state.cs = segment + 0x20;
```

Esto significa que los segmentos de registros tendrán los siguientes valores
luego de que comience la configuración del kernel.

```
fs = es = ds = ss = 0x1000
cs = 0x1020
```

en mi caso, cuando el kernel se carga en `0x10000`

Luego del salto a `start_of_setup`, se necesita hacer lo siguiente:

* Asegurarse de que los valores de todos los registros de segmento sean iguales.
* Si se requiere, configurar la pila correcta(!).
* Configurar el [bss](https://en.wikipedia.org/wiki/.bss).
* Saltar al código en C en [main.c](https://github.com/torvalds/linux/blob/master/arch/x86/boot/main.c)

Echemos un vistazo a la implementación.


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
