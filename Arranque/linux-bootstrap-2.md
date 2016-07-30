Proceso de arranque del kernel. Parte 2.
================================================================================

Primeros pasos en la configuración del kernel
--------------------------------------------------------------------------------
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
`Tabla Global de Descriptores (TGD)` (del inglés `Global Descriptor Table`, GDT)

La TGD es una estructura que reside en memoria. No tiene un lugar fijo en esta, por lo que su
dirección es almacenada en un registro especial llamado `GDTR` (Global Descriptor Table Register). Más adelante
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

4. DPL [2 bits](https://courses.engr.illinois.edu/ece391/fa2014/references/descriptors.pdf)
está en los bits 45-46. este define el nivel de privilegio del segmento. Puede ir
de 0 hasta 3, donde 0 es el más privilegiado.

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


Los registro de segmentos no contienen la dirección base del segmento, como en el modo real. En cambio ellos contienen una estructura especial - `Selector de Segmento`. Cada Descriptor de Segmento tiene asociado un Selector de Segmento. `Selector de Segmento` es una estructura de 16 bits:

```
-----------------------------
|       Índice    | IT | NPS |
-----------------------------
```
Donde:
* **Índice** muestra el número de índice del descriptor respectivo en la TGD.
* **IT**(Indicador de Tabla) muestra en dónde buscar el descriptor. Si es 0, se busca en la Tabla Global de Descriptores (TGD), sino, en la Tabla Local de Descriptores (TLD).
* Y **NPS** es el Nivel de Privilegio del Solicitante (del inglés Requester's Privilege Level, RPL).


Cada registro de segmento tiene una parte visible y otra oculta.
* Visible - El Selector de Segmento se almacena aquí.
* Oculta - Es para el Descriptor de Segmento (la base, el límite, los atributos, banderas).

Para obtener la dirección física en el modo protegido se realizan los siguientes pasos:

* El selector de segmento debe ser cargado en alguno de los registros de segmento.
* La CPU intenta encontrar un descriptor de segmento mediante la dirección de la TGD + el Índice desde el selector de segmento, y carga dicho descriptor en la parte *oculta* del registro de segmento.
* La dirección base (desde el descriptor de segmento) + el *offset* será la dirección lineal del segmento que representa la dirección física (si el paginado está deshabilitado).


Esquemáticamente, esto luce así:

![linear address](http://oi62.tinypic.com/2yo369v.jpg)

El algoritmo para la transición desde el modo real al modo protegido es el siguiente:

* Deshabilitar los interruptores.
* Describir y cargar la TGD con la instrucción `lgdt`.
* Establecer el bit PE (del inglés *Protection Enable*, *Establecer Protección*) a CR0 (*Control Register 0*, *Control de Registro 0*).
* Saltar al código del modo protegido.

En la siguiente parte veremos la transición completa al modo protegido en el kernel linux, pero antes de que pasemos a dicho modo, necesitamos hacer algunas preparaciones adicionales.
We will see the complete transition to protected mode in the linux kernel in the next part, but before we can move to protected mode, we need to do some more preparations.

Observemos el archivo [arch/x86/boot/main.c](https://github.com/torvalds/linux/blob/master/arch/x86/boot/main.c). Podremos ver algunas rutinas encargadas de la inicialización del teclado, del montón, etc... Demos un vistazo a esto.

Copiando los parámetros del arranque en la "zeropage (página zero)"
--------------------------------------------------------------------------------

Iniciaremos desde la rutina `main` en el archivo "main.c". La primera función en ser llamada `main` es [`copy_boot_params(void)`](https://github.com/torvalds/linux/blob/master/arch/x86/boot/main.c#L30). Esta copia el encabezado de configuración del kernel en el campo de la estructura `boot_params`, la cual está definida en el archivo [arch/x86/include/uapi/asm/bootparam.h](https://github.com/torvalds/linux/blob/master/arch/x86/include/uapi/asm/bootparam.h#L113).

La estructura `boot_params` contiene el campo `struct setup_header hdr`. Esta estructura contiene los mismos campos definidos en el [protocolo de arranque de linux](https://www.kernel.org/doc/Documentation/x86/boot.txt), y es rellenada por el cargador de arranque y también en tiempo de compilación del kernel. `copy_boot_params` hace dos cosas:

1. Copia `hdr` desde [header.S](https://github.com/torvalds/linux/blob/master/arch/x86/boot/header.S#L281) a la estructura
`boot_params` en el campo `setup_header`.

2. Actualiza el apuntador a la línea de comandos del kernel si este fue cargado con el antiguo protocolo de línea de comandos.

Es de notar que copia `hdr` con la función `memcpy`, que está definida en el archivo fuente [copy.S](https://github.com/torvalds/linux/blob/master/arch/x86/boot/copy.S). Echemosle un vistazo:


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

Si... justo cuando acababamos de movernos a código en C, y ahora de nuevo a ensamblador :) Primero que todo, podemos ver que `memcpy` y otras rutinas que están definidas aquí comienzan y terminan con dos macros `GLOBAL` y `ENDPROC`. `GLOBAL`es descrita en [arch/x86/include/asm/linkage.h](https://github.com/torvalds/linux/blob/master/arch/x86/include/asm/linkage.h), donde se define la directiva `globl` con su respectiva etiqueta. `ENDPROC` es descrita en [include/linux/linkage.h](https://github.com/torvalds/linux/blob/master/include/linux/linkage.h), donde se marca el símbolo `name` como un nombre de función, y termina con el tamaño del símbolo `name`.

La implementación de `memcpy` es fácil. Primero, se meten los valores de los registros `si` y `di` a la pila para preservar sus valores, porque estos cambiarán durante `memcpy`. `memcpy` (y otras funciones en copy.S) usan la convención de llamadas `fastcall` (ver [fastcall](https://msdn.microsoft.com/en-us/library/6xa169sk.aspx)). Entonces recibe sus parámetros de entrada de los registros `ax`, `dx` y `cx`. Llamar a `memcpy` se ve así:

```c
memcpy(&boot_params.hdr, &hdr, sizeof hdr);
```

Así:
* `ax` contendrá la dirección en bytes de `boot_params.hdr`
* `dx` conentdrá la dirección en bytes de `hdr`
* `cx` contendrá el tamaño de `hdr` en bytes

`memcpy` coloca la dirección de `boot_params.hdr` en el registro `si`, y guarda su tamaño en la pila. Luego lo corre hacia la derecha dos espacios (lo que tiene el efecto de dividir entre 2^2 = 4) y copia 4 bytes de `si` hacia `di`. Luego de esto restauramos nuevamente el tamaño de `hdr`, lo alineamos a 4 bytes y copiamos el resto de los bytes (si es que hay más) desde `si` hacia `di`, uno por uno. Al final restauramos los valores de  `si` y `di` de la pila, y con esto se termina el copiado.

Inicialización de la consola
--------------------------------------------------------------------------------

Luego de que `hdr` es copiado en `boot_params.hdr`, el siguiente paso es inicializar la consola, llamando a la función `console_init`, la cual está definida en [arch/x86/boot/early_serial_console.c](https://github.com/torvalds/linux/blob/master/arch/x86/boot/early_serial_console.c).

Esta intenta buscar la opción `earlyprintk` en la línea de comandos, y si la búsqueda tiene éxito, parsea la dirección del puerto y la [tasa de baudios](https://es.wikipedia.org/wiki/Tasa_de_baudios) del puerto serial y lo inicializa. El valor de la opción `earlyprintk` en la línea de comandos puede ser uno de los siguientes:

* serial,0x3f8,115200
* serial,ttyS0,115200
* ttyS0,115200

Luego de la inicialización del puerto serial, podemos ver la primera salida por pantalla:

```C
if (cmdline_find_option_bool("debug"))
		puts("early console in setup code\n");
```

La definición de `puts` está en [tty.c](https://github.com/torvalds/linux/blob/master/arch/x86/boot/tty.c). Como podemos observar, esta recibe como argumento un `char *`, y lo imprime caracter por caracter, en un ciclo, llamando cada vez a la función `putchar`. Veamos la implementación de `putchar`:

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

`__attribute__((section(".inittext")))` significa que este código estará en la sección `.inittext`. Podemos encontrarlo en el archivo [setup.ld](https://github.com/torvalds/linux/blob/master/arch/x86/boot/setup.ld#L19).

Primero que todo, `putchar` revisa por el caracter `\n`, y si lo encuentra, imprime `\r` antes que él. Luego imprime el caracter (`\n`) en la [pantalla VGA](https://es.wikipedia.org/wiki/Video_Graphics_Array), llamando al BIOS con la [llamada de interrución](https://es.wikipedia.org/wiki/Llamada_de_interrupci%C3%B3n_del_BIOS) `0x10`.

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

Aquí `initregs` toma la estructura `biosregs` y la llena con ceros usando la función `memset` (`initregs`, mostrada aquí, usa `memset`. Véase [initregs](http://lxr.free-electrons.com/source/arch/x86/boot/regs.c#L22)), y luego la llena con los valores de los registros.

```C
	memset(reg, 0, sizeof *reg);
	reg->eflags |= X86_EFLAGS_CF;
	reg->ds = ds();
	reg->es = ds();
	reg->fs = fs();
	reg->gs = gs();
```

Veamos la implementación de [memset](https://github.com/torvalds/linux/blob/master/arch/x86/boot/copy.S#L36):

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

Como puedes ver, se usa la convención de llamadas `fastcall` al igual que `memcpy`, lo que significa que la función obtiene sus parámetros de los registros `ax`, `dx` y `cx`.

Generalmente `memset` es como una implementación de `memcpy`. Guarda los valores del registro `di` en la pila, y coloca el valor del registro `ax` en `di`, que es la dirección de la estructura `biosregs`. Le sigue la instrucción `movzbl`, que copia el valor de `dl` en los 2 bytes de orden inferior del registro `eax`. Los 2 bytes restantes de `eax` se llenan con ceros.

La siguiente instrucción multiplica `eax` con `0x01010101`. Esto debido a que `memset` copiará 4 bytes al mismo tiempo. Por ejemplo, si queremos llenar una estructura con `0x7` usando `memset`, entonces `eax` contendrá el valor `0x00000007`. Luego, si multiplicamos `eax` con `0x01010101`, obtenemos el valor `0x07070707` y ahora sí podemos copiar estos 4 bytes en la estructura. `memset` utiliza las instrucciones `rep; stosl` para copiar `eax` en `es:di`.

El resto de la función `memset` es casi igual que `memcpy`.

Luego de que la estructura `biosregs` es llenada con `memset`, `bios_putchar` llama la interrución [0x10](http://www.ctyme.com/intr/rb-0106.htm), la cual imprime un carácter. Luego revisa si el puerto serial fue inicializado o no, y si fue así, escribe un carácter allí con las instrucciones  [serial_putchar](https://github.com/torvalds/linux/blob/master/arch/x86/boot/tty.c#L30) y `inb/outb`.

Inicialización del heap
--------------------------------------------------------------------------------

Luego de que las secciones de la pila y el [bss](https://en.wikipedia.org/wiki/.bss) se prepararon en [header.S](https://github.com/torvalds/linux/blob/master/arch/x86/boot/header.S) (ver [parte previa](linux-bootstrap-1.md)), el kernel necesita inicializar el [heap](https://github.com/torvalds/linux/blob/master/arch/x86/boot/main.c#L116) con la función [`init_heap`](https://github.com/torvalds/linux/blob/master/arch/x86/boot/main.c#L116).

Primero que todo, `init_heap` revisa que las banderas  [`CAN_USE_HEAP`](https://github.com/torvalds/linux/blob/master/arch/x86/include/uapi/asm/bootparam.h#L21) y [`loadflags`](https://github.com/torvalds/linux/blob/master/arch/x86/boot/header.S#L321) en el archivo de encabezado de inicialización del kernel estén encendidas, y si es así, calcula el final de la pila:

```C
	char *stack_end;

	if (boot_params.hdr.loadflags & CAN_USE_HEAP) {
		asm("leal %P1(%%esp),%0"
		    : "=r" (stack_end) : "i" (-STACK_SIZE));
```

O, en otras palabras `stack_end = esp - STACK_SIZE`.

Luego está el cálculo de `heap_end`:

```c
	heap_end = (char *)((size_t)boot_params.hdr.heap_end_ptr + 0x200);
	if (heap_end > stack_end)
			heap_end = stack_end;
```

Lo que significa que `heap_end_ptr` OR `_end` + `512`(`0x200h`) [1]. El último *if* es para comprobar si `heap_end` es mayor que `stack_end`, en cuyo caso se hace `heap_end = stack_end` para que sean iguales.

Ahora el heap está inicializado y podemos usarlo mediante el método `GET_HEAP`. En los siguientes artículos cómo es usado, cómo nosotros podemos usarlo, y cómo se implementa.

Validación del CPU
--------------------------------------------------------------------------------

El siguiente paso es la validación del cpu mediante la función `validate_cpu` en [arch/x86/boot/cpu.c](https://github.com/torvalds/linux/blob/master/arch/x86/boot/cpu.c).

Esta llama a la función [`check_cpu`](https://github.com/torvalds/linux/blob/master/arch/x86/boot/cpucheck.c#L102), pasandole como parámetros el nivel de cpu en el que nos encontramos y el requerido, y luego revisa que el kernel se ejecute en el nivel correcto.

```c
check_cpu(&cpu_level, &req_level, &err_flags);
	if (cpu_level < req_level) {
    ...
	return -1;
	}
```

`check_cpu` revisa las banderas del cpu, la disponibilidad del [modo largo](https://es.wikipedia.org/wiki/Modo_largo) en el caso de una arquitectura x86_64 (64-bits), revisa el vendedor del procesador y realiza algunas preparaciones para ciertos vendedores, como es el caso de apagar [SSE](https://es.wikipedia.org/wiki/SSE)+[SSE2](https://es.wikipedia.org/wiki/SSE2) para AMD si es que estas no se encuentran, etc.

Detección de memoria
--------------------------------------------------------------------------------

Luego viene la detección de la memoria mediante la función `detect_memory`. Básicamente esta provee un mapa de la RAM disponible al cpu. Usa diferencias interfaces de programación para la detección de memoria, tales como `0xe820`, `0xe801` y `0x88`. Aquí solo veremos la implementación de **0xE820**.

Veamos la implementación de `detect_memory_e820` en el archivo [arch/x86/boot/memory.c](https://github.com/torvalds/linux/blob/master/arch/x86/boot/memory.c). Primero que todo, la función `detect_memory_e820` inicializa la estructura `biosregs` tal como vimos anteriormente, y llena algunos registros con valores que son especiales para la llamada `0xe820`:

```assembly
	initregs(&ireg);
	ireg.ax  = 0xe820;
	ireg.cx  = sizeof buf;
	ireg.edx = SMAP;
	ireg.di  = (size_t)&buf;
```

* `ax` contiene el número de la función (`0xe820` en nuestro caso).
* `cx` contiene el tamaño del buffer (buf en el código) que guardará los datos acerca de la memoria.
* `edx` debe contener el número mágico `SMAP`.
* `es:di` debe contener la dirección del buffer (buf) que guardará datos acerca de la memoria.
* `ebx` debe ser cero.

Luego sigue un ciclo repetitivo donde los datos acerca de la memoria serán recolectados. Comienza con la llamada de interrupción al BIOS `0x15`, la cual escribe una línea desde la tabla de asignación de direcciones. Para obtener la siguiente línea llamamos nuevamente a la interrupción (lo cual hacemos en el ciclo). Antes de la siguiente llamada, `ebx` debe contener el valor retornado previamente:

```C
	intcall(0x15, &ireg, &oreg);
	ireg.ebx = oreg.ebx;
```

Realiza iteraciones en el ciclo para recolectar datos desde la tabla de asignación de direcciones y escribe estos datos en el arreglo `e820entry`:

* Inicio del segmento de memoria.
* Tamaño del segmento de memoria.
* Tipo del segmento de memoria (puede ser reservado, usable, etc...).

Puedes ver el resultado de esto en la salida de `dmesg`, algo como:

```
[    0.000000] e820: BIOS-provided physical RAM map:
[    0.000000] BIOS-e820: [mem 0x0000000000000000-0x000000000009fbff] usable
[    0.000000] BIOS-e820: [mem 0x000000000009fc00-0x000000000009ffff] reserved
[    0.000000] BIOS-e820: [mem 0x00000000000f0000-0x00000000000fffff] reserved
[    0.000000] BIOS-e820: [mem 0x0000000000100000-0x000000003ffdffff] usable
[    0.000000] BIOS-e820: [mem 0x000000003ffe0000-0x000000003fffffff] reserved
[    0.000000] BIOS-e820: [mem 0x00000000fffc0000-0x00000000ffffffff] reserved
```

Inicialización del teclado
--------------------------------------------------------------------------------

Luego sigue la inicialización del teclado, con la llamada de la función [`keyboard_init()`](https://github.com/torvalds/linux/blob/master/arch/x86/boot/main.c#L65). Primeramente, `keyboard_init` inicializa algunos registros llamando a la función `initregs` y a la interrupción [0x16](http://www.ctyme.com/intr/rb-1756.htm), esta última para obtener el estado del teclado:

```c
	initregs(&ireg);
	ireg.ah = 0x02;		/* Obtener estado del teclado */
	intcall(0x16, &ireg, &oreg);
	boot_params.kbd_status = oreg.al;
```

Luego llama a [0x16](http://www.ctyme.com/intr/rb-1757.htm) otra vez para establecer la tasa de repetición y del retraso:
```c
	ireg.ax = 0x0305;	/* Set keyboard repeat rate */
	intcall(0x16, &ireg, NULL);
```

Solicitudes
--------------------------------------------------------------------------------

El siguiente par de pasos son realizar solicitudes para diferentes parámetros. Por ahora no entraremos en los detalles de estas solicitudes; volveremos a ello más adelante. Demos un vistazo a estas funciones:

La rutina [query_mca](https://github.com/torvalds/linux/blob/master/arch/x86/boot/mca.c#L18) llama a la interrución del BIOS [0x15](http://www.ctyme.com/intr/rb-1594.htm) para obtener el número del modelo de la máquina, número de sub-modelo, revisión del BIOS, y otros atributos específicos del hardware:

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

Esta llena el registro `ah` con el valor `0xc0` y llama a la interrupción del BIOS `0x15`. Cuando la interrupción termina de ejecutarse, revisa la [bandera de acarreo](https://en.wikipedia.org/wiki/Carry_flag) (ver también http://learnassembler.com/bandera.html), y si está puesta en 1, significa que el BIOS no soporta (**MCA**)[https://en.wikipedia.org/wiki/Micro_Channel_architecture]. Si la bandera de acarreo está puesta en 0, `ES:BX` contendrá un apuntador a la tabla de información del sistema, que luce más o menos así:

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
 
Luego llamamos a la rutina `set_fs` y le pasamos el valor del registro `es`. La implementación de `set_fs` es bastante simple:

```c
static inline void set_fs(u16 seg)
{
	asm volatile("movw %0,%%fs" : : "rm" (seg));
}
```

Esta función contiene código ensamblador "inline", el cual obtiene el valor del parámetro `seg` y lo coloca en el registro `fs`. Existen muchas funciones en [boot.h](https://github.com/torvalds/linux/blob/master/arch/x86/boot/boot.h) similares a `set_fs`, por ejemplo `set_gs`, `fs`, `gs`, etc.

Al final de `query_mca` esta simplemente copia la tabla apuntada por `es:bx` a la `boot_params.sys_desc_table`.

El siguiente paso es obtener información del [Intel SpeedStep](http://en.wikipedia.org/wiki/SpeedStep) llamando a la función `query_ist`. Primeramente esta revisa el nivel actual del CPU, y si es correcto, llama a `0x15` para obtener la información, y guarda el resultado en `boot_params`.

La siguiente función, [query_apm_bios](https://github.com/torvalds/linux/blob/master/arch/x86/boot/apm.c#L21), obtiene la información del [Advanced Power Management](http://en.wikipedia.org/wiki/Advanced_Power_Management) desde el BIOS. `query_apm_bios` también llama a la interrupción `0x15`, pero con `ah = 0x53` para revisar la instalación del APM (Advanced Power Management). Luego de la ejecución de `0x15`, `query_apm_bios` revisa la firma(!) del `PM` (la cual debe ser `0x504d`), la bandera de acarreo (debe ser 0 si hay soporte para el `APM`) y el valor del registro `cx` (si es 0x02, hay soporte para la interfaz del modo protegido),

Luego llama nuevamente a `0x15`, pero con `ax = 0x5304` para desconectar la interfaz del `APM` y conectar la interfaz del modo protegido de 32-bits. Al final, llena `boot_params.apm_bios_info` con los valores obtenidos del BIOS.

Es de notar que `query_apm_bios` se ejecutará solamente si `CONFIG_APM` o `CONFIG_APM_MODULE` estaban encendidas en el archivo de configuración

```C
#if defined(CONFIG_APM) || defined(CONFIG_APM_MODULE)
	query_apm_bios();
#endif
```

Lo último es la función [`query_edd`](https://github.com/torvalds/linux/blob/master/arch/x86/boot/edd.c#L122), que solicita al BIOS información acerca del `Enhanced Disk Drive` (EDD). Veamos la implementación de `query_edd`:

Ante todo, esta lee la opción [edd](https://github.com/torvalds/linux/blob/master/Documentation/kernel-parameters.txt#L1023) desde la línea de comandos del kernel, y si fue puesta en `off`, entonces `query_edd` simplemente retorna (termina).

Si EDD estaba encendida (`on`), entonces `query_edd` recorre los discos duros soportados por el BIOS, y solicita información del EDD en el siguiente ciclo repetitivo:

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

donde `0x80` es el primer disco duro, y el valor de la macro `EDD_MBR_SIG_MAX` es 16. Este recoge los datos en el arreglo de estructuras de tipo [edd_info](https://github.com/torvalds/linux/blob/master/include/uapi/linux/edd.h#L172). `get_edd_info` se asegura que el EDD está presente invocando la interrupción `0x13` con `ah` igual a `0x41`, y si lo está, `get_edd_info` llama nuevamente a `0x13`, pero con `ah` igual a `0x48` y `si` conteniendo la dirección del buffer donde la información del EDD será guardada.

Conclusión
--------------------------------------------------------------------------------

Este es el final de la segunda parte acerca del interior del kernel Linux. En la siguiente parte veremos la configuración del modo de vídeo y el resto de las preparaciones antes de la transición hacia modo protegido y pasar directamente a él.

Si tienes alguna pregunta o sugerencia, no dudes en escribir un comentario on contáctame en [twitter](https://twitter.com/leolas95).

** Por favor recuerda que el inglés no es mi idioma natal, y lamento cualquier inconveniente en la traducción. Si encuentras algún error por favor envíame un PR a [linux-insides-spanish](https://github.com/leolas95/linux-insides-spanish).**

Links
--------------------------------------------------------------------------------

* [Modo protegido](https://es.wikipedia.org/wiki/Modo_protegido)
* [Modo protegido](http://wiki.osdev.org/Protected_Mode)
* [Modo largo](https://es.wikipedia.org/wiki/Modo_largo)
* [Modo largo](* [Modo largo](https://es.wikipedia.org/wiki/Modo_largo))
* [Buena explicación de los modos del CPU, con código](http://www.codeproject.com/Articles/45788/The-Real-Protected-Long-mode-assembly-tutorial-for)
* [Cómo usar "Expand Down Segments" en CPUs Intel 386 y superiores](http://www.sudleyplace.com/dpmione/expanddown.html)
* [Documentación de earlyprintk](http://lxr.free-electrons.com/source/Documentation/x86/earlyprintk.txt)
* [Parámetros del kernel](https://github.com/torvalds/linux/blob/master/Documentation/kernel-parameters.txt)
* [Consola serial](https://github.com/torvalds/linux/blob/master/Documentation/serial-console.txt)
* [Intel SpeedStep](https://es.wikipedia.org/wiki/SpeedStep)
* [APM](https://es.wikipedia.org/wiki/Advanced_Power_Management)
* [Especificación del EDD](http://www.t13.org/documents/UploadedDocuments/docs2004/d1572r3-EDD3.pdf)
* [Documentación del TLDP para al proceso de arranque de Linux](http://www.tldp.org/HOWTO/Linux-i386-Boot-Code-HOWTO/setup.html) (antiguo)
* [Parte anterior](linux-bootstrap-1.md)

Notas:
--------------------------------------------------------------------------------
[1] No estoy muy seguro a qué se refiere el autor original con esta frase. Posiblemente un error de redacción.
