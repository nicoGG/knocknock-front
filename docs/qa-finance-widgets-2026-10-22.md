# QA de finanzas y widgets — 22 de octubre de 2026

Entorno: simulador dedicado NockNock QA, iPhone SE de tercera generación,
iOS 18.6, interfaz compacta, temas claro y oscuro. Datos ficticios locales;
los simuladores existentes y sus listas personales permanecieron intactos.

## Recorridos comprobados en el simulador

- Crear listas desde plantillas de gastos, cotizaciones y cobros; crear un tipo
  personalizado y seleccionar CLP, EUR y USD.
- Registrar un gasto de CLP 15.000, rechazar un abono superior al saldo,
  guardar abonos de 4.000 y 11.000 y comprobar el cierre y saldo cero.
- Configurar presupuestos general y mensual; verificar disponible y exceso.
- Repartir gastos entre dos participantes y registrar una compensación sin
  alterar el total gastado.
- Adjuntar un PDF y una foto del simulador; abrir el PDF dentro de la app.
- Guardar PDF y XLSX mediante Archivos de iOS; verificar también un ZIP mensual
  con ambos informes y los dos comprobantes originales. XLSX conserva importes
  numéricos y ZIP supera la comprobación de integridad.
- Comparar dos cotizaciones en EUR: precio menor, proveedor, entrega, vigencia
  vencida y estado elegido visibles en pantalla pequeña.
- Validar persona obligatoria en cobros; registrar USD 10,50 con abono de 3,25
  y saldo 7,25; revisar historial y restaurar una versión.
- Configurar vencimiento, alerta y filtro de atrasados; comprobar que pagar el
  saldo elimina la alerta.
- Instalar el widget nativo de pendientes, cambiar lista de origen y destino de
  captura, abrir un registro financiero desde Configuración y guardar una nota
  mediante captura rápida. Completar una nota desde el widget y comprobar su
  estado actualizado en el tablero sin reiniciar.
- Abrir la invitación como invitado: se exige iniciar sesión antes de compartir.

## Errores corregidos

- Desbordamientos de monedas y acciones al crear listas en pantallas pequeñas.
- Diálogos financieros con acciones accesibles al mostrar el teclado y estilo
  coherente con las superficies de la app.
- Comparación móvil en tarjetas legibles; tabla conservada para pantallas amplias.
- Historial de abonos formateado en unidades de moneda en lugar de centavos.
- Bloqueo de nuevos abonos y alertas cuando el registro está cerrado; restaurar
  una versión cerrada también cancela la alerta actual.
- Contraste de la barra de estado y nombres de acciones según el tipo de lista.
- Navegación desde widgets cuando la app está dentro de Configuración, refresco
  del tablero tras una finalización nativa y publicación de cambios locales.
- Confirmación al guardar exportaciones y textos en singular.

## Cobertura automatizada y límites

Se añadieron regresiones para pantalla de 375 × 667, teclado, ambos temas,
cotizaciones compactas, moneda del historial, registros cerrados y restauración.
Las pruebas de widgets cubren apertura en frío, apertura desde pantallas internas,
captura que actualiza el snapshot y finalización sin evento de socket.

Resultado final de 1.3.1+530: `flutter analyze` sin problemas, 379 pruebas
aprobadas, compilación iOS Simulator correcta y APK Android release compilado.
El binario iOS final se reinstaló y abrió conservando los registros de prueba.

No se enviaron invitaciones reales ni se verificaron notificaciones push o
sincronización entre dos cuentas. Esta sesión no reemplaza pruebas en un iPhone
físico ni pruebas de interfaz en Android.
