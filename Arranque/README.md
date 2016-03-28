# Proceso de arranque del kernel 

Este capítulo describe el proceso de arranque del kernel. A continuación verás
un par de artículos que describen todo el ciclo de carga del kernel:

**NOTA DEL TRADUCTOR:** Por ahora, mientras no se complete la traducción del
capítulo, los enlaces dirigen al proyecto original.

* [Del el cargador de arranque al kernel](http://0xax.gitbooks.io/linux-insides/content/Booting/linux-bootstrap-1.html) - describe todo el proceso desde encender la computador, hasta antes de la primera
instrucción del kernel.
* [Primeros pasos en el código de configuración del kernel](http://0xax.gitbooks.io/linux-insides/content/Booting/linux-bootstrap-2.html) - describe los primeros pasos en el código de configuración del
kernel. Verás la inicialización del heap, solicitud de distintos parametros como EDD, IST, etc.
* [Inicialización del modo de vídeo y transición del modo protegido](http://0xax.gitbooks.io/linux-insides/content/Booting/linux-bootstrap-3.html) - describe la inicialización del modo de vídeo en el
código de configuración del kernel, y la transición al modo protegido.
* [Transición al modo de 64 bits](http://0xax.gitbooks.io/linux-insides/content/Booting/linux-bootstrap-4.html) - describe la preparación y transición al modo de 64 bits.
* [Descompresión del kernel](http://0xax.gitbooks.io/linux-insides/content/Booting/linux-bootstrap-5.html) - describe la preparación antes de la descompresión del kernel y la descompresión directa.
