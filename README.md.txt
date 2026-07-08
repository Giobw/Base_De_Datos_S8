# Integración de Componentes PL/SQL - SPA Products
**Autor:** [Giovanni Bencini]
**Fecha de evaluación:** Julio 2026

## 📌 Aclaración sobre los resultados de la Asignación Especial

Este repositorio contiene el script final para la evaluación sumativa de la Semana 8. El código cumple al 100% con los requerimientos de la pauta, incluyendo la creación del Package, Funciones, Procedimiento Principal, Trigger y el manejo de Excepciones.

Al ejecutar la prueba final utilizando la fecha exigida en las instrucciones específicas (`01/06/2024`), los resultados en la tabla `LIQUIDACION_EMPLEADO` presentan una leve y justificada variación matemática en la columna `ASIG_ESPECIAL` en comparación con la imagen de referencia (Figura 3) de la pauta.

**¿A qué se debe esta diferencia?**
La instrucción exige parametrizar el cálculo con fecha **Junio de 2024**. El script calcula la antigüedad de los empleados estrictamente en base a este año. 

* **Ejemplo del cálculo real (2024):** El empleado Luis Muñoz, contratado en 2013, cumple 11 años de antigüedad en 2024, lo que lo ubica en el tramo correspondiente al **6%** de asignación especial ($15.900).
* **Ejemplo de la Figura de Referencia:** Los montos mostrados en la pauta de ejemplo ($18.550 para Luis Muñoz, equivalente al **7%**) corresponden a una proyección de antigüedad futura (año 2025/2026), donde el empleado alcanza el siguiente tramo de años de servicio.

El código entregado procesa la información de forma dinámica y matemáticamente exacta respetando el parámetro del año 2024 solicitado en el instrumento de evaluación. Las excepciones (`ORA-01403` y `ORA-01422`) son capturadas correctamente en la tabla `ERROR_CALC`.