Proceso de arranque del kernel. Parte 3
================================================================================

Inicialización del modo de vídeo y transición al modo protegido
--------------------------------------------------------------------------------

Esta es la tercera parte de la serie del `proceso de arranque del kernel`. In la [parte anterior](https://github.com/leolas95/linux-insides-spanish/blob/master/Arranque/linux-bootstrap-2.md), terminamos justo después de la llamada de la rutina `set_video` en [main.c](https://github.com/torvalds/linux/blob/master/arch/x86/boot/main.c#L181). En esta parte, veremos lo siguiente:
- Inicialización del modo de vídeo en el código de configuración del kernel,
- la preparación antes de cambiar al modo protegido, y
- la transición del modo protegido.

**NOTA** Si no conoces acerca del modo protegido, podrás encontrar información en el [artículo anterior](https://github.com/leolas95/linux-insides-spanish/blob/master/Arranque/linux-bootstrap-2.md). También hay un par de [links](https://github.com/leolas95/linux-insides-spanish/blob/master/Arranque/linux-bootstrap-2.md#links) que te pueden ser útiles.

Como había dicho, empezaremos desde la función `set_video`, definida en el archivo [arch/x86/boot/video.c](https://github.com/torvalds/linux/blob/master/arch/x86/boot/video.c#L315). Podemos ver que comienza obteniendo el modo de vídeo de la estructura `boot_params.hdr`:

```C
u16 mode = boot_params.hdr.vid_mode;
```

la cual ya llenamos en la función `copy_boot_params`, en el artículo anterior. `vid_mode` es un campo obligatorio, que es llenado por el cargador de arranque. Puedes encontrar información acerca de él en el protocolo de arranque del kernel:

```
Offset	Proto	Nombre		Definición
/Size
01FA/2	ALL	    vid_mode	Video mode control
```

Como podremos leer del protocolo de arranque del kernel:

```
vga=<modo>
	aquí <modo> es o bien un entero (en la notación de C, bien sea
	decimal, octal o hexadecimal) o una de las strings
	"normal" (significando 0xFFFF), "ext" (significando 0xFFFE)
	o "ask" (significando 0xFFFD). Este valor deberá ser introducido
	en el campo vid_mode, ya que es usado por el kernel antes de
	que la línea de comandos sea "parseada".
```

Así que podemos agregarle la opción `vga` al archivo de configuración de grub (o de otro cargador de arranque), y este le pasará esta opción a la línea de comandos del kernel. Esta opción puede tener diferentes valores, mencionados en la descripción anterior. Por ejemplo, puede ser un número decimal, hexadecimal (por ej: `0xFFFD`), o un string (por ej: `ask`). Si le pasas `ask` a `vga`, verás un menu como este:

![video mode setup menu](http://oi59.tinypic.com/ejcz81.jpg)

el cual pedirá seleccionar un modo de vídeo. Veremos su implementación, pero antes de ello tenemos que ver algunas otras cosas.

Tipos de datos del kernel.
--------------------------------------------------------------------------------
Anteriormente vimos definiciones de distintos tipos de datos, como `u16` etc. en el código de configuración del kernel. Veamos algunos tipos de datos provistos por el kernel: 


| Tipo | char | short | int | long | u8 | u16 | u32 | u64 |
|------|------|-------|-----|------|----|-----|-----|-----|
|Tamaño|  1   |   2   |  4  |   8  |  1 |  2  |  4  |  8  |

Si lees el código fuente del kernel, verás estos tipos de datos con bastante frecuencia, así que conviene recordarlos.


API del heap
--------------------------------------------------------------------------------

Luego de que obtenemos `vid_mode` de `boot_params.hdr` en la función `set_video`, podemos ver la llamada a la macro `RESET_HEAP`.
`RESET_HEAP` es una macro definida en [boot.h](https://github.com/torvalds/linux/blob/master/arch/x86/boot/boot.h#L199). Se define así:

```C
#define RESET_HEAP() ((void *)( HEAP = _end ))
```

Si has leído la segunda parte, recordarás que inicializamos el heap con la función [`init_heap`](https://github.com/torvalds/linux/blob/master/arch/x86/boot/main.c#L116). Tenemos un par de funciones de utilidades para el heap que están definidas en `boot.h`. Estas son:

```C
#define RESET_HEAP()
```

Como vimos arriba, esta reinicia el heap estableciendo el valor de la variable `HEAP` igual a `_end`, donde `_end` es simplemente `extern char _end[];`.

Luego viene la macro `GET_HEAP`:

```C
#define GET_HEAP(type, n) \
	((type *)__get_heap(sizeof(type),__alignof__(type),(n)))
```

para asignar espacio al heap. Esta llama a la función interna `__get_heap` con 3 parámetros:

* tamaño en bytes de un tipo de datos, para asignar el espacio respectivo
* `__alignof__(tipo)` indica cómo las variables de este tipo están alineadas
* `n` indica cuántos items asignar

La implementación de `__get_heap` es la siguiente:

```C
static inline char *__get_heap(size_t s, size_t a, size_t n)
{
	char *tmp;

	HEAP = (char *)(((size_t)HEAP+(a-1)) & ~(a-1));
	tmp = HEAP;
	HEAP += s*n;
	return tmp;
}
```

y luego veremos su uso, algo parecido a:

```C
saved.data = GET_HEAP(u16, saved.x * saved.y);
```

Tratemos de entender cómo funciona `__get_heap`. Podemos ver que `HEAP` (que es igual a `_end` luego de `RESET_HEAP()`) es la dirección de la memoria alineada de acuerdo al parámetro `a`. Luego de esto guardamos la dirección de memoria de `HEAP` en la variable `tmp` (con la instrucción `tmp = HEAP`), movemos `HEAP` al final del bloque asignado (`HEAP += s*n`) y retornamos `tmp`, que es la dirección inicial de la memoria asignada.

Y la última función es:

```C
static inline bool heap_free(size_t n)
{
	return (int)(heap_end - HEAP) >= (int)n;
}
```

que substrae el valor de `HEAP` a `heap_end` (que lo calculamos en la [parte anterior](https://github.com/leolas95/linux-insides-spanish/blob/master/Arranque/linux-bootstrap-2.md)) y retorna 1 si hay suficiente memoria para `n`.

Y eso es todo. Ya tenemos una API simple para el heap y configurar el modo de vídeo.


Preparación del modo de vídeo
--------------------------------------------------------------------------------

Ya podemos ir directamente a la inicialización del modo de vídeo. Nos habíamos detenido en la llamada a `RESET_HEAP()`, dentro de la función `set_video`. Luego sigue la llamada a `store_mode_params`, que guarda los parámetros del modo de vídeo en la estructura `boot_params.screen_info`, definida en el archivo [include/uapi/linux/screen_info.h](https://github.com/0xAX/linux/blob/master/include/uapi/linux/screen_info.h).

Si observamos la función `store_mode_params`, podemos ver que comienza llamando a `store_cursor_position`. Como podremos deducir por su nombre, esta función se encarga de obtener información acerca del cursor y de guardarla.

Primeramente, `store_cursor_position` crea dos variables de tipo `biosregs` (estas son `ireg` y `oreg`), inicializa el campo `AH` de `ireg` con `0x03` (`ireg.ah = 0x03`) y llama a la interrupción `0x10` del BIOS. Una vez la interrupción se ejecuta con éxito, retorna la fila y columna del cursor en los campos `DH` y `DL` de `oreg`. Estas se guardan en los campos `orig_x` y `orig_y` de la estructura `boot_params.screen_info`. A continuación se muestra el código de la función. 

```C
static void store_cursor_position(void)
{
	struct biosregs ireg, oreg;

	initregs(&ireg);
	ireg.ah = 0x03;
	intcall(0x10, &ireg, &oreg);

	boot_params.screen_info.orig_x = oreg.dl;
	boot_params.screen_info.orig_y = oreg.dh;

	if (oreg.ch & 0x20)
		boot_params.screen_info.flags |= VIDEO_FLAGS_NOCURSOR;

	if ((oreg.ch & 0x1f) > (oreg.cl & 0x1f))
		boot_params.screen_info.flags |= VIDEO_FLAGS_NOCURSOR;
}
```

Para ver el archivo completo, puedes revisar el enlace http://lxr.free-electrons.com/source/arch/x86/boot/video.c. Para ver más acerca de `biosregs`, puedes revisar [boot.h](http://lxr.free-electrons.com/source/arch/x86/boot/boot.h#L231).

Luego de que `store_cursor_position` es ejecutada, se llama a la función `store_video_mode`. Esta simplemente obteiene el modo de vídeo y lo almacena en `boot_params.screen_info.orig_video_mode`.

Luego de esto, se revisa el modo actual de vídeo, y se establece `video_segment` acorde a este, como se muestra:

```C
if (boot_params.screen_info.orig_video_mode == 0x07) {
	/* MDA, HGC, or VGA in monochrome mode */
	video_segment = 0xb000;
} else {
	/* CGA, EGA, VGA and so forth */
	video_segment = 0xb800;
}
```

Luego de que la BIOS transfiere el control al sector de arranque, las siguientes direcciones son para memoria de vídeo:

```
0xB000:0x0000 	32 Kb 	Memoria de vídeo de texto monocromático
0xB800:0x0000 	32 Kb 	Memoria de vídeo de texto a color
```

Por lo tanto, se establece la variable `video_segment` a `0xB000` si el modo de vídeo actual es MDA, HGC, o VGA en modo monocromático, o a `0xB800` si el modo de vídeo actual es a color.

Luego de esto, se debe guardar el tamaño de fuente en `boot_params.screen_info.orig_video_points`:


```C
set_fs(0);
font_size = rdfs16(0x485); /* Font size, BIOS area */
boot_params.screen_info.orig_video_points = font_size;
```

Primero que todo, escribimos 0 en el registro `FS` con la función `set_fs`. Ya vimos funciones como `set_fs` en la parte anterior. Todas ellas esán definidas en [boot.h](https://github.com/0xAX/linux/blob/master/arch/x86/boot/boot.h). Luego obtenemos el tamaño de la fuente, que es el valor en la dirección `0x485`, y lo guardamos en `boot_params.screen_info.orig_video_points`.

```
 x = rdfs16(0x44a);
 y = (adapter == ADAPTER_CGA) ? 25 : rdfs8(0x484)+1;
```

Luego, de la dirección `0x44a` obtenemos el número de columnas, y de `0x484` el número de filas, y las guardamos en `boot_params.screen_info.orig_video_cols` y `boot_params.screen_info.orig_video_lines`, respectivamente. Luego de esto,
finaliza la ejecución de `store_mode_params`.

Luego vemos la función `save_screen`, que simplemente guarda el contenido de la pantalla en el heap. Esta función toma todos los datos que obtuvimos en funciones anteriores, como el número de filas y columnas, y los guarda en la estructura `saved_screen`,
que está definida como:

```C
static struct saved_screen {
	int x, y;
	int curx, cury;
	u16 *data;
} saved;
```

Luego, revisa que el heap tenga suficiente espacio libre para guardar `saved`:

```C
if (!heap_free(saved.x*saved.y*sizeof(u16)+512))
		return;
```

Y si es así, asigna espacio en el heap y guarda `saved` en el.

La siguiente llamada es `probe_cards(0)`, ubicada en [arch/x86/boot/video-mode.c](https://github.com/0xAX/linux/blob/master/arch/x86/boot/video-mode.c#L33). Esto recorre todas las video_cards (colección que representa las tarjetas de vídeo) y obtiene el número de modos que cada una provee; la función sondea los drivers (controladores) de vídeo, y los hace generar listas de los modos que cada una provee. Aquí hay algo interesante: tenemos este ciclo:

```C
for (card = video_cards; card < video_cards_end; card++) {
  /* Recolecta el número de modos */
}
```
pero vemos que `video_cards` no está declarada en ninguna parte. La respuesta es simple: cada modo de vídeo presentado en el código de preparación del kernel para x86 tiene una definición de estructura como esta:

```C
static __videocard video_vga = {
	.card_name	= "VGA",
	.probe		= vga_probe,
	.set_mode	= vga_set_mode,
};
```

donde `__videocard` es una macro:

```C
#define __videocard struct card_info __attribute__((used,section(".videocards")))
```

lo que significa que la estructura `card_info`:

```C
struct card_info {
	const char *card_name;
	int (*set_mode)(struct mode_info *mode);
	int (*probe)(void);
	struct mode_info *modes;
	int nmodes;
	int unsafe;
	u16 xmode_first;
	u16 xmode_n;
};
```

está en el segmento `.videocards`. Echemos un vistazo al guión del enlazador, [arch/x86/boot/setup.ld](https://github.com/0xAX/linux/blob/master/arch/x86/boot/setup.ld), donde podremos encontrar:

```
	.videocards	: {
		video_cards = .;
		*(.videocards)
		video_cards_end = .;
	}
```

Esto significa que `video_cards` es simplemente una dirección de memoria, y que todas las estructuras `card_info` están ubicadas en este segmento. Significa, también, que todas las estructuras `card_info` están ubicadas entre `video_cards` y `video_cards_end` (las direcciones *base* y *final* de un arreglo, si se quiere ver así), por lo que podrán ser recorridas en un ciclo usando estas dos direcciones. Luego de que `probe_cards` se ejecuta, tendremos estructuras como `static __videocard video_vga` con sus campos `nmodes` (el número de modos de vídeo soportados) llenos.

Luego de que termina la ejecución `probe_cards`, nos movemos al ciclo principal en la función `set_video`. Allí hay un ciclo infinito que intenta establecer un modo de vídeo, usando la función `set_mode`, o muestra un menú si le pasamos la opción `vid_mode=ask` al kernel mediante la línea de comandos o si el modo de vídeo no está definido.

La función `set_mode` está definida en [video-mode.c](https://github.com/0xAX/linux/blob/master/arch/x86/boot/video-mode.c#L147) y solo recibe un parámetro, `mode`, que es el número de modos de vídeo (que obtuvimos del menú, o al inicio de `setup_video`).

La función `set_mode` revisa de qué tipo es `mode`:

```C
/* Very special mode numbers... */
if (mode == VIDEO_CURRENT_MODE)
	return 0;	/* Nothing to do... */
else if (mode == NORMAL_VGA)
	mode = VIDEO_80x25;
else if (mode == EXTENDED_VGA)
	mode = VIDEO_8POINT;
```

y llama a la función `raw_set_mode`. Esta a su vez llama a la función `set_mode` para la tarjeta seleccionada (`card->set_mode(&mix)` en el código, donde `mix` es un `struct mode_info *`). Podemos tener acceso a esta funciṕn mediante la estructura `card_info`. Cada modo de vídeo define esta estructura con valores acorde a sí mismo (por ejemplo, para `vga` la función set_mode es `vga_set_mode`. Puedes ver el ejemplo de arriba de la estructura `card_info` para el modo `vga`). `video_vga.set_mode` es `vga_set_mode`, que determina el modo de vga y llama a la función respectiva:

```C
static int vga_set_mode(struct mode_info *mode)
{
	vga_set_basic_mode();

	force_x = mode->x;
	force_y = mode->y;

	switch (mode->mode) {
	case VIDEO_80x25:
		break;
	case VIDEO_8POINT:
		vga_set_8font();
		break;
	case VIDEO_80x43:
		vga_set_80x43();
		break;
	case VIDEO_80x28:
		vga_set_14font();
		break;
	case VIDEO_80x30:
		vga_set_80x30();
		break;
	case VIDEO_80x34:
		vga_set_80x34();
		break;
	case VIDEO_80x60:
		vga_set_80x60();
		break;
	}
	return 0;
}
```

Cada función que establece un modo de vídeo simplemente llama a la interrupción `0x10` del BIOS con un cierto valor en el registro `AH`.

Luego de que establecemos el modo de vídeo, se lo pasamos a `boot_params.hdr.vid_mode`.

Luego se llama a `vesa_store_edid`. Esta función simplemente almacena la información [EDID](https://en.wikipedia.org/wiki/Extended_Display_Identification_Data) (***E**xtended **D**isplay **I**dentification **D**ata*, estructura de datos provista por un monitor, que permite a un computador determinar las capacidades y características de este) para uso del kernel. Luego de esto, se llama otra vez a `store_mode_params`. Finalmente, si `do_restore` está encendido, la pantalla se restaura a un estado previo.

Despues de esto, hemos determinado y establecido el modo de vídeo, y ahora podemos pasar el modo protegido.

Última preparación antes de la transición al modo protegido
--------------------------------------------------------------------------------

Podemos observar la última llamada a función - `go_to_protected_mode` - en in [main.c](https://github.com/torvalds/linux/blob/master/arch/x86/boot/main.c#L184). Tal cual como dice su comentario, esta función realiza las últimas preparaciones e invoca al modo protegido. Veamos de qué trata esto.

La función `go_to_protected_mode` está definida en [arch/x86/boot/pm.c](https://github.com/torvalds/linux/blob/master/arch/x86/boot/pm.c#L104). Esta contiene llamadas a otras funciones que realizan las últimas preparaciones antes de saltar al modo protegido, así que veámoslas y tratemos de entender qué hacen y cómo funcionan.

Primero está la llamada a la función `realmode_switch_hook`. Esta invoca el [*hook*](https://es.wikipedia.org/wiki/Hooking) del cambio al modo real si está presente, y desabilita el [NMI](http://en.wikipedia.org/wiki/Non-maskable_interrupt). Los *hooks* se usan si el cargador de arranque se ejecuta en un entorno hostil. Puedes leer más acerca de los *hooks* en el [protocolo de arranque](https://www.kernel.org/doc/Documentation/x86/boot.txt) (ver el apartado **ADVANCED BOOT LOADER HOOKS**).

El *hook* `realmode_switch` presenta un apuntador a la subrutina lejana de 16 bits en modo real que desabilita las *interrupciones no enmascarables* (_**N**on **M**askable **I**nterrupt_, NMI por sus siglas en ingles). Luego de que el *hook* `realmode_switch` es revisado, ocurre la desabilitación de las interrupciones no enmascarables:

```assembly
asm volatile("cli");
outb(0x80, 0x70);	/* Disable NMI */
io_delay();
```

Lo primero es una línea de ensambladr con la instrucción `cli`, que *limpia* (o resetea) la bandera de interrupciones (`IF`, _**I**nterrupt **Flag**_). Luego de esto, se desactivan las interrupciones externas. La siguiente línea desactiva las NMI.

Una [interrupción](https://es.wikipedia.org/wiki/Interrupci%C3%B3n) es una señal a la CPU emitida por hardware o software, indicandole que ha ocurrido un evento que requiere atención inmediata. Luego de recibir la señal, la CPU suspende la instrucción actual, guarda su estado y transfiere el control al [manejador de interrupción](https://en.wikipedia.org/wiki/Interrupt_handler) apropiado. Cuando el manejador de interrupción ha terminado su trabajo, transfiere el control a la instrucción que había sido interrumpida. Las interrupciones no enmascarables (NMI) son interrupciones que siempre son procesadas, intependientemente de la permisología. **No pueden ser ignoradas**, y típicamente son usadas para indicar errores de hardware de los cuales no podemos recuperarnos. No entraremos en muchos detalles de las interrupciones por ahora, dejándolo para los siguientes artículos.

Volvamos al código. Podemos observar que la segunda línea está escribiendo el byte `0x80` (bit desabilitado (!)) a la dirección `0x70` (registro de direcciones CMOS). Luego de eso, se llama a la función `io_delay`. Esta causa un pequeño o dilación:

```C
static inline void io_delay(void)
{
	const u16 DELAY_PORT = 0x80;
	asm volatile("outb %%al,%0" : : "dN" (DELAY_PORT));
}
```

Escribir cualquier byte en el puerto `0x80`, debería causar un retraso de 1 microsegundo. Así que podemos escribir cualquier valor (en este caso el valor del registro `AL`) en el puerto `0x80`. Luego de este retraso, la función `realmode_switch_hook` termina y podemos pasar a la siguiente función.

La siguiente función es `enable_a20`, que habilita la [línea A20](http://en.wikipedia.org/wiki/A20_line). Ésta función está definida en [arch/x86/boot/a20.c](https://github.com/torvalds/linux/blob/master/arch/x86/boot/a20.c); esta intenta habilitar la puerta A20 mediante diferentes métodos. El primero es la función `a20_test_short`, que revisa si A20 está habilitada o no usando la función `a20_test`:

```C
static int a20_test(int loops)
{
	int ok = 0;
	int saved, ctr;

	set_fs(0x0000);
	set_gs(0xffff);

	saved = ctr = rdfs32(A20_TEST_ADDR);

    while (loops--) {
		wrfs32(++ctr, A20_TEST_ADDR);
		io_delay();	/* Serialize and make delay constant */
		ok = rdgs32(A20_TEST_ADDR+0x10) ^ ctr;
		if (ok)
			break;
	}

	wrfs32(saved, A20_TEST_ADDR);
	return ok;
}
```

Lo primero es colocar el valor `0x0000` en el registro `FS` y el valor `0xffff` en el registro `GS` (con `set_fs(0x0000)` y `set_gs(0xffff)`, respectivamente). Luego leemos el valor en la dirección `A20_TEST_ADDR` (`rdfs32(A20_TEST_ADDR)`), (que, por cierto, está definida más arriba en el archivo como `#define A20_TEST_ADDR	(4*0x80)`, por lo que tiene un valor de `0x200`, o 512 en decimal) y colocamos este valor en las variables `saved` y `ctr`.

Luego escribimos un valor actualizado de `ctr` en `fs:gs` con la función `wrfs32`, luego esperamos por un microsegundo, y leemos el valor del registro `GS` mediante la dirección `A20_TEST_ADDR+0x10`; si este resultado es distinto de cero significa que ya hemos habilitado la línea A20. Si A20 continúa desabilitada, intentamos habilitarla usando otro método, que podrás encontrar en el mismo archivo `a20.c`. Por ejemplo, con una llamada a la interrupción `0x15` de la BIOS, con `AX=0x2041`; mediante el controlador del teclado (usando la función `empty_8042()`), etc.

Si la función `enabled_a20` falla, se muestra un mensaje de error y se llama la función `die`. Podrás recordar que la vimos en el primer archivo de código fuente con el que empezamos - [arch/x86/boot/header.S](https://github.com/torvalds/linux/blob/master/arch/x86/boot/header.S):

```assembly
die:
	hlt
	jmp	die
	.size	die, .-die
```

Cuando la puerta A20 es habilitada exitosamente, se llama a la función `reset_coprocessor`:

 ```C
outb(0, 0xf0);
outb(0, 0xf1);
```

Esta función *limpia* el coprocesador matemático, escribiendo `0` en la dirección `0xf0`, y luego lo resetea escribiendo `0` en `0xf1`.

Luego de esto, la función `mask_all_interrupts` es llamada:

```C
outb(0xff, 0xa1);       /* Mask all interrupts on the secondary PIC */
outb(0xfb, 0x21);       /* Mask all but cascade on the primary PIC */
```

Esto enmascara todas las interrupciones en los [PIC](https://es.wikipedia.org/wiki/Controlador_programable_de_interrupciones) (_**P**rogrammable **I**nterrupt **C**ontroller_, por sus siglas en inglés) primario y secundario, exceptuando IRQ2 en el primario.

Al final de todas estas preparaciones, podemos ver transición como tal al modo protegido.

And after all of these preparations, we can see the actual transition into protected mode, mediante las llamadas a las funciones 
`setup_idt`, `setup_gdt` y `protected_mode_jump`:

```C
static void setup_idt(void)
{
	...
	/* Actual transition to protected mode... */
	setup_idt();
	setup_gdt();
	protected_mode_jump(boot_params.hdr.code32_start,
		    (u32)&boot_params + (ds() << 4));
}
```

Preparar la Tabla de Descriptores de Interrupción
--------------------------------------------------------------------------------

Ahora preparamos la [Tabla de Descriptores de Interrupció](https://en.wikipedia.org/wiki/Interrupt_descriptor_table) (_**I**nterrupt **D**escriptor **T**able_, IDT, por sus siglas en inglés), con la función `setup_idt`:

```C
static void setup_idt(void)
{
	static const struct gdt_ptr null_idt = {0, 0};
	asm volatile("lidtl %0" : : "m" (null_idt));
}
```
que inicializa la Tabla de Descriptores de Interrupción (que describe los manejadores de interrupciones, etc). Por
ahora la IDT no se _instala_ (veremos esto luego); simplemente la _cargamos_ con la instrucción `lidtl`. `null_idt`
contiene la dirección y tamaño de la IDT, pero en este momento estos son cero. `null_idt` es una estructura de
tipo `gdt_ptr`, definida como:

```C
struct gdt_ptr {
	u16 len;
	u32 ptr;
} __attribute__((packed));
```

Donde podemos ver el campo de 16 bits que indica la longitud de la tabla (`len`) y el apuntador a ella, de 32 bits
(en los siguientes artículos se verán más detalles acerca de la IDT y las interrupciones).
` __attribute__((packed))` significa que el tamaño de `gdt_ptr` es el mínimo requerido para la tabla. Así, el tamaño
`gdt_ptr` será de 6 bytes, o 48 bits (los 32 bits de ptr más los 16 de len). (Luego cargaremos el apuntador a
`gdt_ptr` en el registro `GDTR`, que podrás recordar de artículos anteriores que tiene un tamaño de 48 bits).

Preparar la Tabla de Descriptores Globales
--------------------------------------------------------------------------------

Los siguiente es la inicialización de la [Tabla Global de Descriptores](https://en.wikipedia.org/wiki/Global_Descriptor_Table) (GDT. Ver también [GDT en OSdev](http://wiki.osdev.org/GDT_Tutorial)). Podemos ver la función `setup_gdt`, que inicializa la GDT (también puedes
leer más de ella en [Proceso de arranque del Kernel. Parte 2](https://github.com/leolas95/linux-insides-spanish/blob/master/Arranque/linux-bootstrap-2.md#modo-protegido)). En esta función hay
una definición del arreglo `boot_gdt`, que a su vez contiene la definición de tres segmentos:

```C
	static const u64 boot_gdt[] __attribute__((aligned(16))) = {
		[GDT_ENTRY_BOOT_CS] = GDT_ENTRY(0xc09b, 0, 0xfffff),
		[GDT_ENTRY_BOOT_DS] = GDT_ENTRY(0xc093, 0, 0xfffff),
		[GDT_ENTRY_BOOT_TSS] = GDT_ENTRY(0x0089, 4096, 103),
	};
```

Esto es para los segmentos de código (CS), datos (DS) y de estado de la tarea (TSS, _Task State Segment_). Por
ahora no usaremos el TSS; como podemos ver en el [comentario de la función](https://github.com/torvalds/linux/commit/88089519f302f1296b4739be45699f06f728ec31), solo fue agregado para
_complacer_ a Intel VT (_**I**ntel **V**irtualization **T**echnology_, Tecnología de Virtualización de Intel).
Revisemos el `boot_gdt`. Primero que todo, nótese que este tiene el atributo `__attribute__((aligned(16)))` . Esto
significa que esta estructura será alineada a 16 bytes. Veamos un ejemplo sencillo:

```C
#include <stdio.h>

struct aligned {
	int a;
}__attribute__((aligned(16)));

struct nonaligned {
	int b;
};

int main(void)
{
	struct aligned    a;
	struct nonaligned na;

	printf("Not aligned - %zu \n", sizeof(na));
	printf("Aligned - %zu \n", sizeof(a));

	return 0;
}
```

Técnicamente, una estructura que contiene un solo `int` debería ocupar 4 bytes (por supuesto, dependiendo de la
arquitectura), pero aquí, `struct aligned a` ocupará 16 bytes, como se muestra:

```
$ gcc test.c -o test && test
Not aligned - 4
Aligned - 16
```

Continuando con el arreglo boot_gdt`. `GDT_ENTRY_BOOT_CS` está en la posición índice - 2, `GDT_ENTRY_BOOT_DS` en la
posición `GDT_ENTRY_BOOT_CS + 1` + 1, etc. Se comienza desde 2 porque lo primero hay es un descriptor nulo obligatorio
(índice - 0), y el segundo espacio es no usado (índice - 1).

`GDT_ENTRY` es una macro que recibe banderas, una base y un límite y construye una entrada o registro de la GDT. Por
ejemplo, veamos la entrada para el segmento de código:

```C
[GDT_ENTRY_BOOT_CS] = GDT_ENTRY(0xc09b, 0, 0xfffff)
```

`GDT_ENTRY` recibe los siguientes valores como argumentos:

* base  - 0
* límite - 0xfffff
* bandera - 0xc09b

¿Qué significa esto? La dirección base del segmento es 0, y el límite (que también se puede ver como el tamaño del
segmento) is `0xfffff` (1 MB). Veamos el valor de la bandera. Este es `0xc09b`, que en binario sería:


```
1100 0000 1001 1011
```

Tratemos de entender qué significa cada bit. Iremos de izquierda a derecha:


* 1    - (G) Bit de granularidad (Ver [esto](https://pdos.csail.mit.edu/6.828/2007/readings/i386/s05_01.htm) y [esto](http://ece-research.unm.edu/jimp/310/slides/micro_arch2.html))
* 1    - (D) si es 0 -> segmento de 16 bits; si es 1 -> segmento de 32 bits
* 0    - (L) si es 1, ejecución en modo de 64 bits
* 0    - (AVL) (available) disponible para uso del _usuario_ (sistema operativo)
* 0000 - longitud de 4 bits, del bit 16 al 19 en el descriptor
* 1    - (P) presencia de segmento en memoria ([ver más](https://pdos.csail.mit.edu/6.828/2007/readings/i386/s05_01.htm))
* 00   - (DPL) - nivel de privilegio; 0 es el más privilegiado
* 1    - (S) segmento de código o datos, no es un segmento del sistema
* 101  - tipo de lectura/ejecución del segmento
* 1    - bit de accesado

Puedes leer más acerca de cada bit en el [artículo previo](https://github.com/leolas95/linux-insides-spanish/blob/master/Arranque/linux-bootstrap-2.md) o en los [Manuales para el Desarrollador de Software para
arquitecturas Intel® 64 y IA-32](http://www.intel.com/content/www/us/en/processors/architectures-software-developer-manuals.html).

Luego de esto obtenemos la longitud de la GDT con:

```C
gdt.len = sizeof(boot_gdt)-1;
```

que obtiene el tamaño de `boot_gdt` y le resta 1 (para obtener la última **dirección válida** en la GDT).

Luego obtenemos un apuntador a la GDT con:

```C
gdt.ptr = (u32)&boot_gdt + (ds() << 4);
```

Aquí simplemente obtenemos la dirección de `boot_gdt` y le sumamos la dirección del segmento de datos (ds) desplazada
4 bits a la izquierda (recuerda que estamos en modo real).

Finalmente, ejecutamos la instrucción `lgdtl` para cargar la GDT en el registro GDTR:

```C
asm volatile("lgdtl %0" : : "m" (gdt));
```

Verdadera transición al modo protegido
--------------------------------------------------------------------------------

This is the end of the `go_to_protected_mode` function. We loaded IDT, GDT, disable interruptions and now can switch the CPU into protected mode. The last step is calling the `protected_mode_jump` function with two parameters:

```C
protected_mode_jump(boot_params.hdr.code32_start, (u32)&boot_params + (ds() << 4));
```

which is defined in [arch/x86/boot/pmjump.S](https://github.com/torvalds/linux/blob/master/arch/x86/boot/pmjump.S#L26). It takes two parameters:

* address of protected mode entry point
* address of `boot_params`

Let's look inside `protected_mode_jump`. As I wrote above, you can find it in `arch/x86/boot/pmjump.S`. The first parameter will be in the `eax` register and second is in `edx`.

First of all we put the address of `boot_params` in the `esi` register and the address of code segment register `cs` (0x1000) in `bx`. After this we shift `bx` by 4 bits and add the address of label `2` to it (we will have the physical address of label `2` in the `bx` after this) and jump to label `1`. Next we put data segment and task state segment in the `cs` and `di` registers with:

```assembly
movw	$__BOOT_DS, %cx
movw	$__BOOT_TSS, %di
```

As you can read above `GDT_ENTRY_BOOT_CS` has index 2 and every GDT entry is 8 byte, so `CS` will be `2 * 8 = 16`, `__BOOT_DS` is 24 etc.

Next we set the `PE` (Protection Enable) bit in the `CR0` control register:

```assembly
movl	%cr0, %edx
orb	$X86_CR0_PE, %dl
movl	%edx, %cr0
```

and make a long jump to protected mode:

```assembly
	.byte	0x66, 0xea
2:	.long	in_pm32
	.word	__BOOT_CS
```

where
* `0x66` is the operand-size prefix which allows us to mix 16-bit and 32-bit code,
* `0xea` - is the jump opcode,
* `in_pm32` is the segment offset
* `__BOOT_CS` is the code segment.

After this we are finally in the protected mode:

```assembly
.code32
.section ".text32","ax"
```

Let's look at the first steps in protected mode. First of all we set up the data segment with:

```assembly
movl	%ecx, %ds
movl	%ecx, %es
movl	%ecx, %fs
movl	%ecx, %gs
movl	%ecx, %ss
```

If you paid attention, you can remember that we saved `$__BOOT_DS` in the `cx` register. Now we fill it with all segment registers besides `cs` (`cs` is already `__BOOT_CS`). Next we zero out all general purpose registers besides `eax` with:

```assembly
xorl	%ecx, %ecx
xorl	%edx, %edx
xorl	%ebx, %ebx
xorl	%ebp, %ebp
xorl	%edi, %edi
```

And jump to the 32-bit entry point in the end:

```
jmpl	*%eax
```

Remember that `eax` contains the address of the 32-bit entry (we passed it as first parameter into `protected_mode_jump`).

That's all. We're in the protected mode and stop at it's entry point. We will see what happens next in the next part.

Conclusion
--------------------------------------------------------------------------------

This is the end of the third part about linux kernel insides. In next part, we will see first steps in the protected mode and transition into the [long mode](http://en.wikipedia.org/wiki/Long_mode).

If you have any questions or suggestions write me a comment or ping me at [twitter](https://twitter.com/0xAX).

**Please note that English is not my first language, And I am really sorry for any inconvenience. If you find any mistakes, please send me a PR with corrections at [linux-insides](https://github.com/0xAX/linux-internals).**

Links
--------------------------------------------------------------------------------

* [VGA](http://en.wikipedia.org/wiki/Video_Graphics_Array)
* [VESA BIOS Extensions](http://en.wikipedia.org/wiki/VESA_BIOS_Extensions)
* [Data structure alignment](http://en.wikipedia.org/wiki/Data_structure_alignment)
* [Non-maskable interrupt](http://en.wikipedia.org/wiki/Non-maskable_interrupt)
* [A20](http://en.wikipedia.org/wiki/A20_line)
* [GCC designated inits](https://gcc.gnu.org/onlinedocs/gcc-4.1.2/gcc/Designated-Inits.html)
* [GCC type attributes](https://gcc.gnu.org/onlinedocs/gcc/Type-Attributes.html)
* [Previous part](linux-bootstrap-2.md)

