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

First is the call to the `realmode_switch_hook` function in `go_to_protected_mode`. This function invokes the real mode switch hook if it is present and disables [NMI](http://en.wikipedia.org/wiki/Non-maskable_interrupt). Hooks are used if the bootloader runs in a hostile environment. You can read more about hooks in the [boot protocol](https://www.kernel.org/doc/Documentation/x86/boot.txt) (see **ADVANCED BOOT LOADER HOOKS**).

The `realmode_switch` hook presents a pointer to the 16-bit real mode far subroutine which disables non-maskable interrupts. After `realmode_switch` hook (it isn't present for me) is checked, disabling of Non-Maskable Interrupts(NMI) occurs:

```assembly
asm volatile("cli");
outb(0x80, 0x70);	/* Disable NMI */
io_delay();
```

At first there is an inline assembly instruction with a `cli` instruction which clears the interrupt flag (`IF`). After this, external interrupts are disabled. The next line disables NMI (non-maskable interrupt).

An interrupt is a signal to the CPU which is emitted by hardware or software. After getting the signal, the CPU suspends the current instruction sequence, saves its state and transfers control to the interrupt handler. After the interrupt handler has finished it's work, it transfers control to the interrupted instruction. Non-maskable interrupts (NMI) are interrupts which are always processed, independently of permission. It cannot be ignored and is typically used to signal for non-recoverable hardware errors. We will not dive into details of interrupts now, but will discuss it in the next posts.

Let's get back to the code. We can see that second line is writing `0x80` (disabled bit) byte to `0x70` (CMOS Address register). After that, a call to the `io_delay` function occurs. `io_delay` causes a small delay and looks like:

```C
static inline void io_delay(void)
{
	const u16 DELAY_PORT = 0x80;
	asm volatile("outb %%al,%0" : : "dN" (DELAY_PORT));
}
```

To output any byte to the port `0x80` should delay exactly 1 microsecond. So we can write any value (value from `AL` register in our case) to the `0x80` port. After this delay `realmode_switch_hook` function has finished execution and we can move to the next function.

The next function is `enable_a20`, which enables [A20 line](http://en.wikipedia.org/wiki/A20_line). This function is defined in [arch/x86/boot/a20.c](https://github.com/torvalds/linux/blob/master/arch/x86/boot/a20.c) and it tries to enable the A20 gate with different methods. The first is the `a20_test_short` function which checks if A20 is already enabled or not with the `a20_test` function:

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

First of all we put `0x0000` in the `FS` register and `0xffff` in the `GS` register. Next we read the value in address `A20_TEST_ADDR` (it is `0x200`) and put this value into the `saved` variable and `ctr`.

Next we write an updated `ctr` value into `fs:gs` with the `wrfs32` function, then delay for 1ms, and then read the value from the `GS` register by address `A20_TEST_ADDR+0x10`, if it's not zero we already have enabled the A20 line. If A20 is disabled, we try to enable it with a different method which you can find in the `a20.c`. For example with call of `0x15` BIOS interrupt with `AH=0x2041` etc.

If the `enabled_a20` function finished with fail, print an error message and call function `die`. You can remember it from the first source code file where we started - [arch/x86/boot/header.S](https://github.com/torvalds/linux/blob/master/arch/x86/boot/header.S):

```assembly
die:
	hlt
	jmp	die
	.size	die, .-die
```

After the A20 gate is successfully enabled, the `reset_coprocessor` function is called:
 ```C
outb(0, 0xf0);
outb(0, 0xf1);
```
This function clears the Math Coprocessor by writing `0` to `0xf0` and then resets it by writing `0` to `0xf1`.

After this, the `mask_all_interrupts` function is called:
```C
outb(0xff, 0xa1);       /* Mask all interrupts on the secondary PIC */
outb(0xfb, 0x21);       /* Mask all but cascade on the primary PIC */
```
This masks all interrupts on the secondary PIC (Programmable Interrupt Controller) and primary PIC except for IRQ2 on the primary PIC.

And after all of these preparations, we can see the actual transition into protected mode.

Set up Interrupt Descriptor Table
--------------------------------------------------------------------------------

Now we set up the Interrupt Descriptor table (IDT). `setup_idt`:

```C
static void setup_idt(void)
{
	static const struct gdt_ptr null_idt = {0, 0};
	asm volatile("lidtl %0" : : "m" (null_idt));
}
```

which sets up the Interrupt Descriptor Table (describes interrupt handlers and etc.). For now the IDT is not installed (we will see it later), but now we just the load IDT with the `lidtl` instruction. `null_idt` contains address and size of IDT, but now they are just zero. `null_idt` is a `gdt_ptr` structure, it as defined as:
```C
struct gdt_ptr {
	u16 len;
	u32 ptr;
} __attribute__((packed));
```

where we can see the 16-bit length(`len`) of the IDT and the 32-bit pointer to it (More details about the IDT and interruptions will be seen in the next posts). ` __attribute__((packed))` means that the size of `gdt_ptr` is the minimum required size. So the size of the `gdt_ptr` will be 6 bytes here or 48 bits. (Next we will load the pointer to the `gdt_ptr` to the `GDTR` register and you might remember from the previous post that it is 48-bits in size).

Set up Global Descriptor Table
--------------------------------------------------------------------------------

Next is the setup of the Global Descriptor Table (GDT). We can see the `setup_gdt` function which sets up GDT (you can read about it in the [Kernel booting process. Part 2.](linux-bootstrap-2.md#protected-mode)). There is a definition of the `boot_gdt` array in this function, which contains the definition of the three segments:

```C
	static const u64 boot_gdt[] __attribute__((aligned(16))) = {
		[GDT_ENTRY_BOOT_CS] = GDT_ENTRY(0xc09b, 0, 0xfffff),
		[GDT_ENTRY_BOOT_DS] = GDT_ENTRY(0xc093, 0, 0xfffff),
		[GDT_ENTRY_BOOT_TSS] = GDT_ENTRY(0x0089, 4096, 103),
	};
```

For code, data and TSS (Task State Segment). We will not use the task state segment for now, it was added there to make Intel VT happy as we can see in the comment line (if you're interested you can find commit which describes it - [here](https://github.com/torvalds/linux/commit/88089519f302f1296b4739be45699f06f728ec31)). Let's look at `boot_gdt`. First of all note that it has the `__attribute__((aligned(16)))` attribute. It means that this structure will be aligned by 16 bytes. Let's look at a simple example:
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

Technically a structure which contains one `int` field must be 4 bytes, but here `aligned` structure will be 16 bytes:

```
$ gcc test.c -o test && test
Not aligned - 4
Aligned - 16
```

`GDT_ENTRY_BOOT_CS` has index - 2 here, `GDT_ENTRY_BOOT_DS` is `GDT_ENTRY_BOOT_CS + 1` and etc. It starts from 2, because first is a mandatory null descriptor (index - 0) and the second is not used (index - 1).

`GDT_ENTRY` is a macro which takes flags, base and limit and builds GDT entry. For example let's look at the code segment entry. `GDT_ENTRY` takes following values:

* base  - 0
* limit - 0xfffff
* flags - 0xc09b

What does this mean? The segment's base address is 0, and the limit (size of segment) is - `0xffff` (1 MB). Let's look at the flags. It is `0xc09b` and it will be:

```
1100 0000 1001 1011
```

in binary. Let's try to understand what every bit means. We will go through all bits from left to right:

* 1    - (G) granularity bit
* 1    - (D) if 0 16-bit segment; 1 = 32-bit segment
* 0    - (L) executed in 64 bit mode if 1
* 0    - (AVL) available for use by system software
* 0000 - 4 bit length 19:16 bits in the descriptor
* 1    - (P) segment presence in memory
* 00   - (DPL) - privilege level, 0 is the highest privilege
* 1    - (S) code or data segment, not a system segment
* 101  - segment type execute/read/
* 1    - accessed bit

You can read more about every bit in the previous [post](linux-bootstrap-2.md) or in the [Intel® 64 and IA-32 Architectures Software Developer's Manuals 3A](http://www.intel.com/content/www/us/en/processors/architectures-software-developer-manuals.html).

After this we get the length of the GDT with:

```C
gdt.len = sizeof(boot_gdt)-1;
```

We get the size of `boot_gdt` and subtract 1 (the last valid address in the GDT).

Next we get a pointer to the GDT with:

```C
gdt.ptr = (u32)&boot_gdt + (ds() << 4);
```

Here we just get the address of `boot_gdt` and add it to the address of the data segment left-shifted by 4 bits (remember we're in the real mode now).

Lastly we execute the `lgdtl` instruction to load the GDT into the GDTR register:

```C
asm volatile("lgdtl %0" : : "m" (gdt));
```

Actual transition into protected mode
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

