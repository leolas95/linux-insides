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
o simplemente reporta un problema. Lo apreciaría mucho.
Todos los artículos también estarán accesibles por [linux-insides](https://github.com/0xAX/linux-insides),
y si encuentras algún error con el contenido del artículo
o con mi gramática, sientete libre de enviar un pull request.

*Es importante notar que esto no es una documentación oficial, simplemente es compartir y ganar conocimiento.*

**Aptitudes requeridas:**

* Comprender código en lenguaje C
* Comprender código en lenguaje ensamblador (sintaxis de AT&T)


De cualquier modo, si acabas de empezar a aprender algunas herramientas(!!), trataré de explicar algunas partes durante este y los siguientes artículos. Bien, terminada la pequeña introducción,
ya podemos empezar a profundizar en el kernel y en temas de bajo nivel.

Todo el código es del kernel -3.18. Si hay algún cambio, actualizaré el artículo apropiadamente.

El mágico botón de encendido, ¿Qué ocurre luego?
--------------------------------------------------------------------------------

A pesar de que estos son una serie de artículos acerca del kernel Linux, no
empezaremos desde el código del kernel (por lo menos no en este párrafo). Ok,
presionaste el mágico botón de encendido en tu laptop o computador de
escritorio y este ha empezado a trabajar. Luego de que la tarjeta madre
envía una señal a la [fuente de poder](https://es.wikipedia.org/wiki/Fuente_de_alimentaci%C3%B3n)
esta provee a la computadora con la cantidad debida de electricidad.
Una vez que la tarjeta madre recibe la señal correcta de energía,
esta intenta iniciar el CPU. Este reinicia todos los datos residuales
en sus registros y establece valores predefinidos para cada uno de ellos.

La línea de [CPUs 80386](https://es.wikipedia.org/wiki/Intel_80386)
(y los pos teriores a esta) establecen una serie de datos predefinidos
en los registros del CPU luego de un reinicio:

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
Obtenemos `0xfffffff0`, que son 4GB - 16 bytes. Este punto es llamado el [Vector de reinicio](https://en.wikipedia.org/wiki/Reset_vector).
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
; Nota: este ejemplo está escrito con la sintaxis de ensamblador de Intel.
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

Con la herramienta `objdump` podrás observar el volcado
de memoria binario de esta operación:

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
* Saltar al código en C ubicado en [main.c](https://github.com/torvalds/linux/blob/master/arch/x86/boot/main.c)

Echemos un vistazo a la implementación.


Alineación de los registros de segmentos
--------------------------------------------------------------------------------

Primero que todo, se asegura que los registros de segmentos `ds` y `es` apunten
a la misma dirección y desabilitan las interrupciones con la instrucción
`cli`:

```assembly
	movw	%ds, %ax
	movw	%ax, %es
	cli	
```
Como dije anteriormente, grub2 carga el código de cnfiguración del kernel en
la dirección `0x10000` y `cs` en `0x1020`, porque la ejecución no inicia
desdel el comienzo del archivo, sino desde:

```
_start:
	.byte 0xeb
	.byte start_of_setup-1f
```
`jmp`, que está a una distancia relativa de 512 bytes de [4d 5a](https://github.com/torvalds/linux/blob/master/arch/x86/boot/header.S#L47),
también necesita alinear `cs` desde `0x10200` hasta `0x10000`, como a todos
los demás registros de segmentos. Luego de eso, configuramos la pila:

```assembly
	pushw	%ds
	pushw	$6f
	lretw
```

Esto introduce el valor `ds` a la pila, junto con la dirección de la etiqueta
[6](https://github.com/torvalds/linux/blob/master/arch/x86/boot/header.S#L494)
y ejecuta la intrucción `lretw`. Cuando llamamos a `lretw`, esta carga
la dirección de la etiqueta `6` en el registro del
[puntero de instrucciones](https://en.wikipedia.org/wiki/Program_counter)
y luego a `cs` con el valor de `ds`. Luego de esto, tendremos a `ds` y a `cs`
con los mismos valores.


Configuración de la pila
--------------------------------------------------------------------------------

De hecho, casi todo el código de configuración es para preparar el entorno
del lenguaje C en modo real. El [siguiente paso](https://github.com/torvalds/linux/blob/master/arch/x86/boot/header.S#L467) 
es revisar que el valor del registro `ss` sea correcto, y corregir la pila si
no es así:

```assembly
	movw	%ss, %dx
	cmpw	%ax, %dx
	movw	%sp, %dx
	je	2f
```

Esto puede llevar a tres escenarios distintos:


* El valor de `ss` válido; 0x10000 (así como los otros registros de segmentos, además de `cs`)
* El valor de `ss` es inválido y la bandera `CAN_USE_HEAP` está establecida (ver debajo)
* Es valor de `ss` es inválido y la bandera `CAN_USE_HEAP` no está establecida (ver debajo)

Echemos un vistazo a estos tres casos:

1. La dirección de `ss` (0x10000) es correcta. En este caso, nos movemos a la
etiqueta [2](https://github.com/torvalds/linux/blob/master/arch/x86/boot/header.S#L481).

```
2: 	andw	$~3, %dx
	jnz	3f
	movw	$0xfffc, %dx
3:  movw	%ax, %ss
	movzwl %dx, %esp
	sti
```

Aquí podemos ver el alineamiento de `dx` (que contiene a `sp`, dado por el cargador de arranque)
a 4 bytes, y también se revisa si su valor es cero. Si es así, entonces
colocamos a `0xfffc` (una dirección alineada a 4 bytes, antes del tamaño máximo
del segmento - 64 KB) en `dx`. Sino, continuamos usando el `sp` dado por el
cargador de arranque (en mi caso, 0xf7f4). Luego de esto, colocamos el valor de
`ax` en `ss`, el cual almacena la dirección de segmento `0x10000`, que es la
correcta, y por lo tanto crea un registro `sp` correcto. Ahora si tenemos una pila válida:

![stack](http://oi58.tinypic.com/16iwcis.jpg).

2. En el segundo escenario (`ss` != `ds`), lo primero que hacemos es colocar
el valor de [_end](https://github.com/torvalds/linux/blob/master/arch/x86/boot/setup.ld#L52)
(que es la dirección del final del código de configuración) en el registro
`dx`, y revisamos el el campo de cabecera `loadflags` con la instrucción `testb`
para ver si podemos usar el montón o no.
[loadflags](https://github.com/torvalds/linux/blob/master/arch/x86/boot/header.S#L321)
es un *bitmask* en un archivo de cabecera, que está definido de la siguiente forma:

```C
#define LOADED_HIGH	    (1<<0)
#define QUIET_FLAG	    (1<<5)
#define KEEP_SEGMENTS	(1<<6)
#define CAN_USE_HEAP	(1<<7)
```

Y, como podemos leer en el protocolo de arranque:

```
Field name:	loadflags

  This field is a bitmask.

  Bit 7 (write): CAN_USE_HEAP
	Set this bit to 1 to indicate that the value entered in the
	heap_end_ptr is valid.  If this field is clear, some setup code
	functionality will be disabled.
```
Si el bit `CAN_USE_HEAP` está encendido, entonces se coloca `heap_end_ptr`
en `dx` , el cual apunta a `_end`, y agrega `STACK_SIZE` (el tamaño mínimo de la pila - 512 bytes),
a este (`dx`). Luego de esto, si `dx` no es una bandera
[*carry*](https://en.wikipedia.org/wiki/Carry_flag)
(también ver [aquí](://www.quora.com/Assembly-Language/When-are-the-carry-and-overflow-flags-set))
(y no lo será, ya que `dx = _end + 512`), entonces se salta a la etiqueta `2`,
como en el caso anterior, y se crea una pila válida.

![stack](http://oi62.tinypic.com/dr7b5w.jpg)

3. Cuando `CAN_USE_HEAP` no está encendido, usamos una pila mínima de `_end` hasta
`_end + STACK_SIZE`:

![minimal stack](http://oi60.tinypic.com/28w051y.jpg)

Configuración del segmento BSS
--------------------------------------------------------------------------------

Los últimos dos pasos necesarios antes de que podamos saltar al código principal en C son
configurar el área del segmento [BSS](https://en.wikipedia.org/wiki/.bss), y revisar
la firma "mágica". Primero, la revisión de la firma:

```assembly
cmpl	$0x5a5aaa55, setup_sig
jne	setup_bad
```

Esto simplemente compara [setup_sig](https://github.com/torvalds/linux/blob/master/arch/x86/boot/setup.ld#L39) con el *número mágico* `0x5a5aaa55`.
Si estos **no son iguales**, ocurre un *error fatal*.

Si estos **sí son iguales**, sabiendo que tenemos un conjunto de registros de segmento
válidos, y una pila, entonces solamente tenemos que configurar la sección BSS antes
de movernos al código en C:

La sección BSS es usada para guardar datos almacenados estáticamente, y sin inicializar. Linux
se asegura cuidadosamente de que esta área de memoria sea primero limpiada (borrada), usando el
siguiente código:

```assembly
	movw	$__bss_start, %di
	movw	$_end+3, %cx
	xorl	%eax, %eax
	subw	%di, %cx
	shrw	$2, %cx
	rep; stosl
```

Primero que todo, la dirección de [__bss_start](https://github.com/torvalds/linux/blob/master/arch/x86/boot/setup.ld#L47)
es movida a `di`, y la de `_end + 3` (+ 3 - se alínea a 4 bytes) a `cx`.
El registro `eax` es limpiado (usando una instrucción `xor`), y el tamaño de la sección
bss (`cx` - `di`) es calculado y puesto en `cx`. Luego, `cx` se divide entre cuatro
(porque es el tamaño de una *palabra*), y la instrucción `stosl` se usa
repetidamente, almacenando el valor de `eax` (cero) en la dirección apuntada por
`di`, automáticamente aumentando `di` por cuatro (esto ocurre hasta que `cx`
llega a cero). El efecto de todo esto es que un montón de ceros son escritos
en todas las *palabras* de la memoria desde `__bss_start` hasta `_end`:

![bss](http://oi59.tinypic.com/29m2eyr.jpg)

Salto a main
--------------------------------------------------------------------------------

Eso es todo, ya tenemos la pila y la sección BSS, por lo que ya podemos saltar
a la función `main()` de C:

```assembly
	calll main
```

La función `main()` se localiza en [arch/x86/boot/main.c](https://github.com/torvalds/linux/blob/master/arch/x86/boot/main.c). Lo que hace lo puedes leer en el siguiente artículo.


Conclusión
--------------------------------------------------------------------------------

Este es el final de la primera parte acerca del funcionamiento interno del kernel Linux.
si tienes alguna duda o pregunta, contáctame en twitter ([0xAX](https://twitter.com/0xAX)),
envíame un [correo](anotherworldofworld@gmail.com) o simplemente reporta un problema.
En la siguiente parte veremos el primer código en C que se ejecuta en la configuración
del kernel, la implementación de algunas rutinas de memoria tales como `memset`,
`memcpy`, `earlyprintk`, inicialización temprana de la consola y mucho más.

**Por favor, recuerda que el inglés no es mi idioma natal, lamento cualquier inconveniente.
Si encuentras un error por favor envía un PR a [linux-internals](https://github.com/0xAX/linux-internals).**

**Please note that English is not my first language and I am really sorry for any inconvenience. If you found any mistakes please send me PR to [linux-internals](https://github.com/0xAX/linux-internals).**

Links
--------------------------------------------------------------------------------

  * [Manual de referencia del programador de Intel 80386 - 1986](http://css.csail.mit.edu/6.858/2014/readings/i386.pdf)
  * [Cargador de arranque mínimo para la arcquitectura Intel®](https://www.cs.cmu.edu/~410/doc/minimal_boot.pdf)
  * [8086](http://en.wikipedia.org/wiki/Intel_8086)
  * [80386](http://en.wikipedia.org/wiki/Intel_80386)
  * [Reset vector](http://en.wikipedia.org/wiki/Reset_vector)
  * [Real mode](http://en.wikipedia.org/wiki/Real_mode)
  * [Protocolo de arranque del kernel Linux](https://www.kernel.org/doc/Documentation/x86/boot.txt)
  * [Manual del desarrollador de CoreBoot](http://www.coreboot.org/Developer_Manual)
  * [Lista de interrupciones de Ralf Brown](http://www.ctyme.com/intr/int.htm)
  * [Fuente de poder](http://en.wikipedia.org/wiki/Power_supply://es.wikipedia.org/wiki/Fuente_de_alimentaci%C3%B3n()
  * [Señal correcta de energía](http://en.wikipedia.org/wiki/Power_good_signal)
