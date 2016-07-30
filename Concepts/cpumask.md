CPU masks
================================================================================

Introducción
--------------------------------------------------------------------------------

Las `Cpumasks` es un método especial proporcionado por el kernel Linux de almacenar información acerca de las CPUs del sistema. Los archivos fuente y cabeceras relevantes que contienen la API para la manipulación de `Cpumasks` son:

* [include/linux/cpumask.h](https://github.com/torvalds/linux/blob/master/include/linux/cpumask.h)
* [lib/cpumask.c](https://github.com/torvalds/linux/blob/master/lib/cpumask.c)
* [kernel/cpu.c](https://github.com/torvalds/linux/blob/master/kernel/cpu.c)

Como dice el comentario de [include/linux/cpumask.h](https://github.com/torvalds/linux/blob/master/include/linux/cpumask.h): Las Cpumasks proporcionan un mapa de bits apropiado para representar el conjunto de CPU's en un sistema, una posición de bit por número de CPU. Ya vimos un poco acerca de las cpumask en la función `boot_cpu_init` de la parte [entry point del Kernel](http://0xax.gitbooks.io/linux-insides/content/Initialization/linux-initialization-4.html). Esta función establece los estados de la CPU "online", "active", "present" y "possible" para el arranque.

```C
set_cpu_online(cpu, true);
set_cpu_active(cpu, true);
set_cpu_present(cpu, true);
set_cpu_possible(cpu, true);
```

`set_cpu_possible` es un conjunto de IDs de cpu que pueden ser conectados en cualquier momento durante el proceso arranque del sistema. `cpu_present` representa que CPUs están conectadas en este momento. `cpu_online` representa un subconjunto de `cpu_present` y indica que CPUs están listas para ejecución. Esta mascara depende de la opción de configuración `CONFIG_HOTPLUG_CPU` y si está deshabilitada `possible == present` y `active == online`. La implementación de todas estas funciones son muy similares. Cada función comprueba el segundo parámetro. Si es `true`, llama a `cpumask_set_cpu` en caso contrario a `cpumask_clear_cpu` .

Hay dos formas de crear una `cpumask`. La primera es usar `cpumask_t`. Definida como:

```C
typedef struct cpumask { DECLARE_BITMAP(bits, NR_CPUS); } cpumask_t;
```

Esta envuelve la estructura `cpumask` la cual contiene la máscara de bits `bits`. La macro `DECLARE_BITMAP` recibe dos parámetros:

* nombre del mapa de bits.
* número de bits.

y crea un array de `unsigned long` con el nombre dado. Su implementación es sencilla:

```C
#define DECLARE_BITMAP(name,bits) \
        unsigned long name[BITS_TO_LONGS(bits)]
```

donde `BITS_TO_LONGS`:

```C
#define BITS_TO_LONGS(nr)       DIV_ROUND_UP(nr, BITS_PER_BYTE * sizeof(long))
#define DIV_ROUND_UP(n,d) (((n) + (d) - 1) / (d))
```

Como nos estamos enfocando en la arquitectura  `x86_64`, `unsigned long` tiene un tamaño de 8 bytes y nuestro array sólo contendra un elemento:

```
(((8) + (8) - 1) / (8)) = 1
```

La macro `NR_CPUS` representa el número de CPUs en el sistema y depende de la macro `CONFIG_NR_CPUS` definida en [include/linux/threads.h](https://github.com/torvalds/linux/blob/master/include/linux/threads.h) y se ve como esto:

```C
#ifndef CONFIG_NR_CPUS
        #define CONFIG_NR_CPUS  1
#endif

#define NR_CPUS         CONFIG_NR_CPUS
```

La segunda forma de definir una cpumask es usar directamente las macros `DECLARE_BITMAP` y `to_cpumask` donde esta última convierte el mapa de bits dado a `struct cpumask *`:

```C
#define to_cpumask(bitmap)                                              \
        ((struct cpumask *)(1 ? (bitmap)                                \
                            : (void *)sizeof(__check_is_bitmap(bitmap))))
```

Podemos ver que el operador ternario siempre es `true`. La función `__check_is_bitmap` está definida como: 

```C
static inline int __check_is_bitmap(const unsigned long *bitmap)
{
        return 1;
}
```

Y devuelve `1` todo el tiempo. Necesitamos esta función por un sólo propósito: en tiempo de compilación comprueba que el `bitmap` dado es un mapa de bits, en otras palabras comprueba que el `bitmap` dado es del tipo - `unsigned long *`. Así que acabamos de pasar `cpu_possible_bits` a la macro `to_cpumask` para convertir un array de `unsigned long` a `struct cpumask *`.

cpumask API
--------------------------------------------------------------------------------

Como podemos definir una cpumask con uno de estos métodos, el kernel Linux provee una API para manipular esta cpumask. Vamos a considerar una de las funciones presentadas anteriormente. Por ejemplo la `set_cpu_online`. Esta función recibe dos parámetros: 

* Número de CPU;
* Estado de la CPU;

La implementación de esta función se ve como:

```C
void set_cpu_online(unsigned int cpu, bool online)
{
	if (online) {
		cpumask_set_cpu(cpu, to_cpumask(cpu_online_bits));
		cpumask_set_cpu(cpu, to_cpumask(cpu_active_bits));
	} else {
		cpumask_clear_cpu(cpu, to_cpumask(cpu_online_bits));
	}
}
```

Antes que nada comprueba el segundo parámetro (el estado) y dependiendo de este llamara a `cpumask_set_cpu` o  `cpumask_clear_cpu`. Aquí podemos ver el 'casteo' a `struct cpumask *` en el segundo parámetro en la función `cpumask_set_cpu`. En nuestro caso éste es `cpu_online_bits` el cual es un mapa de bits definido como.

```C
static DECLARE_BITMAP(cpu_online_bits, CONFIG_NR_CPUS) __read_mostly;
```

La función `cpumask_set_cpu` hace sólo una llamada a la función `set_bit`:

```C
static inline void cpumask_set_cpu(unsigned int cpu, struct cpumask *dstp)
{
        set_bit(cpumask_check(cpu), cpumask_bits(dstp));
}
```

La función `set_bit` también recibe dos parámetros, y coloca un bit dado (primer parámetro) en la memoria (segundo parámetro o el mapa de bits `cpu_online_bits` en este caso). Podemos ver aquí que antes de la llamada a `set_bit`, sus dos parámetros se pasaran a las macros:

* cpumask_check;
* cpumask_bits.

Vamos a considerar estas dos macros. La macro `cpumask_check` en nuestro caso no hace nada, sólo devuelve el parámetro dado. La macro `cpumask_bits` simplemente devuelve el campo `bits` de la estructura `struct cpumask *` dada:

```C
#define cpumask_bits(maskp) ((maskp)->bits)
```

Ahora vamos a mirar en la implementación de `set_bit`:

```C
 static __always_inline void
 set_bit(long nr, volatile unsigned long *addr)
 {
         if (IS_IMMEDIATE(nr)) {
                asm volatile(LOCK_PREFIX "orb %1,%0"
                        : CONST_MASK_ADDR(nr, addr)
                        : "iq" ((u8)CONST_MASK(nr))
                        : "memory");
        } else {
                asm volatile(LOCK_PREFIX "bts %1,%0"
                        : BITOP_ADDR(addr) : "Ir" (nr) : "memory");
        }
 }
```

Esta función se ve espantosa, pero no es tan difícil como parece. Primero de todo pasa el `nr` (número del bit) a la macro `IS_IMMEDIATE` la cual simplemente llama a la función de GCC (builtin) `__builtin_constant_p`:

```C
#define IS_IMMEDIATE(nr)    (__builtin_constant_p(nr))
```

`__builtin_constant_p` comprueba que el parámetro dado es constante en tiempo de compilación. Como nuestra `cpu` no es constante en tiempo de compilación, se ejecutara la cláusula `else`:

```C
asm volatile(LOCK_PREFIX "bts %1,%0" : BITOP_ADDR(addr) : "Ir" (nr) : "memory");
```

Intentemos entender como funciona paso a paso:

`LOCK_PREFIX` es la instrucción `lock` del x86. Esta instrucción le dice a la cpu que ocupe el bus del sistema mientras la instruccion(es) van a ser ejecutadas. Esto permite que la CPU sincronice el acceso a memoria, previniendo accesos simultáneos de múltiples procesadores (o dispositivos - el controlador DMA por ejemplo) a una celda de memoria.

`BITOP_ADDR` convierte el parámetro dado al tipo `(*(volatile long *)` y añade la especificación `+m`. `+` significa que este operando es leído y escrito por la instrucción. `m` muestra que es un operando de memoria. `BITOP_ADDR` esta definido como:

```C
#define BITOP_ADDR(x) "+m" (*(volatile long *) (x))
```

Luego tenemos el especificador `memory`. Éste indica al compilador que el código ensamblador realiza lecturas o escrituras de memoria a ítems distintos a los listados en los operandos de entrada y salida (por ejemplo, acceder a la memoria apuntada por uno de los parámetros de entrada).

`Ir` - Operando de registro inmediato.


La instrucción `bts` establece un bit dado en una cadena de bits y almacena el valor de un bit dado en el flag `CF`.  Acabamos de pasar el número de cpu (el cual es zero en nuestro caso) y después de ejecutar `set_bit`, establece el bit zero en la cpumask `cpu_online_bits`. Esto significa que la primera cpu esta online en este momento.

A parte de la API `set_cpu_*`, la cpumask provee otra API para su manipulación. Vamos a considerarlo en breve.

API adicional de la cpumask
--------------------------------------------------------------------------------

La cpumask provee de un conjunto de macros para obtener el número de CPUs en varios estados. Por ejemplo:

```C
#define num_online_cpus()	cpumask_weight(cpu_online_mask)
```

Esta macro devuelve la cantidad de CPUs `online`. Esta llama a la función `cpumask_weight` pasándole como parámetro el mapa de bits `cpu_online_mask` (lee sobre esto). La función `cpumask_weight` hace una llamada a la función con dos parámetros `bitmap_weight`:

* cpumask bitmap;
* `nr_cpumask_bits` - en nuestro caso es `NR_CPUS` .

```C
static inline unsigned int cpumask_weight(const struct cpumask *srcp)
{
	return bitmap_weight(cpumask_bits(srcp), nr_cpumask_bits);
}
```

y calcula el número de bits en el mapa de bits dado. Además de `num_online_cpus`, la cpumask provee macros para todos los posibles estados de la CPU:

* num_possible_cpus;
* num_active_cpus;
* cpu_online;
* cpu_possible.

y muchos otros.

Además de esto, el kernel Linux provee las siguientes APIs para la manipulación de `cpumask`:

* `for_each_cpu` - itera sobre todas las cpu en una máscara (mask en inglés);
* `for_each_cpu_not` - itera sobre todas las cpu en una máscara complementada;
* `cpumask_clear_cpu` - limpia una cpu en una cpumask;
* `cpumask_test_cpu` - comprueba una cpu en una máscara;
* `cpumask_setall` - establece todas las cpus en una máscara;
* `cpumask_size` - devuelve el tamaño en bytes que se debe asignar para poder almacenar una 'struct cpumask';

y muchísimas otras..

Links
--------------------------------------------------------------------------------

* [cpumask documentation](https://www.kernel.org/doc/Documentation/cpu-hotplug.txt)
