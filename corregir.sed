# Este archivo se usa para eliminar las lineas con conflictos al actualizar
# del repositorio original de 0xAX.

# La forma en que lo ejecuto es:
# sed -i.bak --file=corregir.sed <archivo a corregir>
# La opcion -i es para que sed haga los cambios en el mismo archivo (por defecto
# los muestra en pantalla). '.bak' es para indicarle que primero haga un
# respaldo del archivo, con extension .bak (se puede usar cualquier otra).

# Elimina todas las lineas que esten entre '<<<<<< HEAD' y '======='
# incluyendo las lineas que contienen los patrones
/^<<<<<<< HEAD$/,/^=======$/d

# Elimina todas las lineas que contienen el patron '>>>>>>> upstream/<branch>
/^>>>>>>> upstream\//d
