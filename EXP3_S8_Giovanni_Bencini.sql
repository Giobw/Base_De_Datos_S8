-- ============================================================================
-- EVALUACIÓN SUMATIVA: INTEGRACIÓN DE COMPONENTES PL/SQL
-- CASO PRÁCTICO: SPA PRODUCTS
-- ============================================================================

-- ============================================================================
-- 1. CREACIÓN DEL PACKAGE (ESPECIFICACIÓN Y CUERPO)
-- Centraliza variables globales, el cálculo del promedio y el log de errores
-- ============================================================================
CREATE OR REPLACE PACKAGE PKG_SPA_PRODUCTS IS
    -- Variables globales dinámicas
    v_fecha_proceso DATE := SYSDATE;
    v_mes_proceso   NUMBER := EXTRACT(MONTH FROM SYSDATE);
    v_anno_proceso  NUMBER := EXTRACT(YEAR FROM SYSDATE);
    v_promedio_ventas NUMBER;
    
    -- Declaración de subprogramas públicos
    FUNCTION FN_PROMEDIO_VENTAS_ANNO_ANT RETURN NUMBER;
    PROCEDURE SP_REGISTRAR_ERROR(p_rutina VARCHAR2, p_msj_oracle VARCHAR2, p_msj_usr VARCHAR2);
END PKG_SPA_PRODUCTS;
/

CREATE OR REPLACE PACKAGE BODY PKG_SPA_PRODUCTS IS

    FUNCTION FN_PROMEDIO_VENTAS_ANNO_ANT RETURN NUMBER IS
        v_promedio NUMBER;
    BEGIN
        SELECT NVL(AVG(db.VALOR_TOTAL), 0) INTO v_promedio
        FROM DETALLE_BOLETA db
        JOIN BOLETA b ON db.NRO_BOLETA = b.NRO_BOLETA
        WHERE EXTRACT(YEAR FROM b.FECHA) = v_anno_proceso - 1;
        
        RETURN v_promedio;
    EXCEPTION
        WHEN OTHERS THEN
            RETURN 0;
    END FN_PROMEDIO_VENTAS_ANNO_ANT;

    PROCEDURE SP_REGISTRAR_ERROR(p_rutina VARCHAR2, p_msj_oracle VARCHAR2, p_msj_usr VARCHAR2) IS
    BEGIN
        INSERT INTO ERROR_CALC (CORREL_ERROR, RUTINA_ERROR, DESCRIP_ERROR, DESCRIP_USER)
        VALUES (SEQ_ERROR.NEXTVAL, p_rutina, SUBSTR(p_msj_oracle, 1, 300), SUBSTR(p_msj_usr, 1, 300));
    END SP_REGISTRAR_ERROR;

END PKG_SPA_PRODUCTS;
/

-- ============================================================================
-- 2. FUNCIONES ALMACENADAS INDEPENDIENTES
-- ============================================================================

-- A) Función para calcular Asignación Especial por Antigüedad
CREATE OR REPLACE FUNCTION FN_PCT_ESPECIAL(p_run_empleado VARCHAR2) RETURN NUMBER IS
    v_pct NUMBER := 0;
    v_anios NUMBER;
BEGIN
    SELECT ROUND(MONTHS_BETWEEN(PKG_SPA_PRODUCTS.v_fecha_proceso, FECHA_CONTRATO) / 12)
    INTO v_anios
    FROM EMPLEADO
    WHERE RUN_EMPLEADO = p_run_empleado;
    
    SELECT PORC_ANTIGUEDAD INTO v_pct
    FROM PCT_ANTIGUEDAD
    WHERE v_anios BETWEEN ANNOS_ANTIGUEDAD_INF AND ANNOS_ANTIGUEDAD_SUP;
    
    RETURN v_pct;
EXCEPTION
    WHEN NO_DATA_FOUND THEN 
        PKG_SPA_PRODUCTS.SP_REGISTRAR_ERROR('FN_PCT_ESPECIAL', 'ORA-01403: No se ha encontrado ningún dato', 'Error al calcular PCT ESPECIAL');
        RETURN 0;
    WHEN OTHERS THEN
        PKG_SPA_PRODUCTS.SP_REGISTRAR_ERROR('FN_PCT_ESPECIAL', SQLERRM, 'Error al calcular PCT ESPECIAL');
        RETURN 0; 
END FN_PCT_ESPECIAL;
/

-- B) Función para Porcentaje por Nivel de Estudios (Solo afiliados FONASA)
CREATE OR REPLACE FUNCTION FN_ESTUDIOS(p_run_empleado VARCHAR2) RETURN NUMBER IS
    v_pct NUMBER := 0;
BEGIN
    SELECT pne.PORC_ESCOLARIDAD INTO v_pct
    FROM EMPLEADO e
    JOIN PREVISION_SALUD ps ON e.COD_SALUD = ps.COD_SALUD
    JOIN PCT_NIVEL_ESTUDIOS pne ON e.COD_ESCOLARIDAD = pne.COD_ESCOLARIDAD
    WHERE e.RUN_EMPLEADO = p_run_empleado 
      AND UPPER(ps.NOM_SALUD) = 'FONASA';
      
    RETURN v_pct;
EXCEPTION
    WHEN TOO_MANY_ROWS THEN
        PKG_SPA_PRODUCTS.SP_REGISTRAR_ERROR('FN_ESTUDIOS', 'ORA-01422: la recuperación exacta devuelve un número mayor de filas que el solicitado', 'Error al calcular nivel de estudios');
        RETURN 0;
    WHEN NO_DATA_FOUND THEN 
        RETURN 0;
    WHEN OTHERS THEN
        PKG_SPA_PRODUCTS.SP_REGISTRAR_ERROR('FN_ESTUDIOS', SQLERRM, 'Error al calcular nivel de estudios');
        RETURN 0;
END FN_ESTUDIOS;
/

-- C) Función Validadora (Determina si el 7% de ventas actuales supera el promedio anterior)
CREATE OR REPLACE FUNCTION FN_VALIDA_VENTA(p_run_empleado VARCHAR2) RETURN NUMBER IS
    v_ventas_actuales NUMBER := 0;
BEGIN
    SELECT NVL(SUM(MONTO_TOTAL_BOLETA), 0) INTO v_ventas_actuales
    FROM BOLETA
    WHERE RUN_EMPLEADO = p_run_empleado
      AND EXTRACT(YEAR FROM FECHA) = PKG_SPA_PRODUCTS.v_anno_proceso;
      
    IF (v_ventas_actuales * 0.07) > PKG_SPA_PRODUCTS.v_promedio_ventas THEN
        RETURN 1; 
    ELSE
        RETURN 0; 
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        RETURN 0;
END FN_VALIDA_VENTA;
/

-- ============================================================================
-- 3. PROCEDIMIENTO ALMACENADO PRINCIPAL
-- Centraliza la lógica de negocio y procesa las liquidaciones de todos los empleados
-- ============================================================================
CREATE OR REPLACE PROCEDURE SP_PROCESAR_LIQUIDACIONES (p_fecha DATE) AUTHID CURRENT_USER IS
    CURSOR cur_empleados IS
        SELECT e.RUN_EMPLEADO, e.NOMBRE || ' ' || e.PATERNO || ' ' || e.MATERNO AS NOMBRE_COMPLETO,
               e.SUELDO_BASE, te.DESCRIPCION AS DESC_TIPO
        FROM EMPLEADO e
        JOIN TIPO_EMPLEADO te ON e.TIPO_EMPLEADO = te.TIPO_EMPLEADO;
        
    v_asig_especial NUMBER;
    v_asig_estudios NUMBER;
    v_total_haberes NUMBER;
    v_porc_esp      NUMBER;
BEGIN
    -- Sincronización de variables globales del Package
    PKG_SPA_PRODUCTS.v_fecha_proceso := p_fecha;
    PKG_SPA_PRODUCTS.v_mes_proceso := EXTRACT(MONTH FROM p_fecha);
    PKG_SPA_PRODUCTS.v_anno_proceso := EXTRACT(YEAR FROM p_fecha);
    PKG_SPA_PRODUCTS.v_promedio_ventas := PKG_SPA_PRODUCTS.FN_PROMEDIO_VENTAS_ANNO_ANT();

    -- Preparación del entorno de destino
    EXECUTE IMMEDIATE 'TRUNCATE TABLE LIQUIDACION_EMPLEADO';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE ERROR_CALC';

    -- Procesamiento iterativo de empleados
    FOR rec IN cur_empleados LOOP
        v_asig_especial := 0;
        v_asig_estudios := 0;
        
        -- Regla de Negocio: La asignación especial aplica EXCLUSIVAMENTE a vendedores
        IF UPPER(rec.DESC_TIPO) LIKE '%VEND%' THEN
            -- Se calcula antigüedad para forzar posibles excepciones de captura
            v_porc_esp := FN_PCT_ESPECIAL(rec.RUN_EMPLEADO);
            
            -- Validación de meta de ventas contra promedio global
            IF FN_VALIDA_VENTA(rec.RUN_EMPLEADO) = 1 THEN
                v_asig_especial := ROUND(rec.SUELDO_BASE * (v_porc_esp / 100));
            END IF;
        END IF;

        -- Cálculo de asignación por estudios (Controla interiormente afiliación a FONASA)
        v_asig_estudios := ROUND(rec.SUELDO_BASE * (FN_ESTUDIOS(rec.RUN_EMPLEADO) / 100));
        
        -- Totalización de haberes
        v_total_haberes := rec.SUELDO_BASE + v_asig_especial + v_asig_estudios;
        
        -- Inserción de resultados en tabla final
        INSERT INTO LIQUIDACION_EMPLEADO (
            MES, ANNO, RUN_EMPLEADO, NOMBRE_EMPLEADO, SUELDO_BASE,
            ASIG_ESPECIAL, ASIG_ESTUDIOS, TOTAL_HABERES
        ) VALUES (
            PKG_SPA_PRODUCTS.v_mes_proceso, PKG_SPA_PRODUCTS.v_anno_proceso, 
            rec.RUN_EMPLEADO, rec.NOMBRE_COMPLETO, rec.SUELDO_BASE,
            v_asig_especial, v_asig_estudios, v_total_haberes
        );
    END LOOP;
    
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        PKG_SPA_PRODUCTS.SP_REGISTRAR_ERROR('SP_PROCESAR_LIQUIDACIONES', SQLERRM, 'Fallo general en proceso central');
        COMMIT;
END SP_PROCESAR_LIQUIDACIONES;
/

-- ============================================================================
-- 4. DESARROLLO DE TRIGGERS
-- Controla operaciones DML en días hábiles y actualiza totales si hay UPDATE
-- ============================================================================
CREATE OR REPLACE TRIGGER TRG_MANTENCION_PRODUCTOS
BEFORE INSERT OR DELETE OR UPDATE OF VALOR_UNITARIO ON PRODUCTO
FOR EACH ROW
DECLARE
    v_promedio NUMBER;
    v_dia VARCHAR2(15);
BEGIN
    v_dia := UPPER(TO_CHAR(SYSDATE, 'DY', 'NLS_DATE_LANGUAGE=ENGLISH'));
    
    -- Restricción de operaciones de creación o eliminación entre Lunes y Viernes
    IF INSERTING OR DELETING THEN
        IF v_dia IN ('MON', 'TUE', 'WED', 'THU', 'FRI') THEN
            IF INSERTING THEN
                RAISE_APPLICATION_ERROR(-20501, 'TABLA DE PRODUCTO PROTEGIDA');
            ELSIF DELETING THEN
                RAISE_APPLICATION_ERROR(-20500, 'TABLA DE PRODUCTO PROTEGIDA');
            END IF;
        END IF;
    END IF;
    
    -- Automatización en caso de modificación del valor unitario
    IF UPDATING('VALOR_UNITARIO') THEN
        BEGIN
            SELECT NVL(AVG(db.VALOR_TOTAL), 0) INTO v_promedio
            FROM DETALLE_BOLETA db
            JOIN BOLETA b ON db.NRO_BOLETA = b.NRO_BOLETA
            WHERE db.COD_PRODUCTO = :NEW.COD_PRODUCTO
              AND EXTRACT(YEAR FROM b.FECHA) = (EXTRACT(YEAR FROM SYSDATE) - 1);
              
            IF :NEW.VALOR_UNITARIO > (v_promedio * 0.10) THEN
                UPDATE DETALLE_BOLETA
                SET VALOR_TOTAL = CANTIDAD * :NEW.VALOR_UNITARIO
                WHERE COD_PRODUCTO = :NEW.COD_PRODUCTO;
            END IF;
        EXCEPTION
            WHEN OTHERS THEN
                PKG_SPA_PRODUCTS.SP_REGISTRAR_ERROR('TRG_MANTENCION_PRODUCTOS', SQLERRM, 'Error calculando detalles del producto ID ' || :NEW.COD_PRODUCTO);
        END;
    END IF;
END TRG_MANTENCION_PRODUCTOS;
/

-- ============================================================================
-- 5. BLOQUE ANÓNIMO DE EJECUCIÓN DE PRUEBAS
-- Ejecuta el procesamiento de remuneraciones parametrizado a Junio de 2024
-- ============================================================================
BEGIN
    SP_PROCESAR_LIQUIDACIONES(TO_DATE('01/06/2024', 'DD/MM/YYYY'));
END;
/

-- Consultas de verificación de resultados
SELECT * FROM LIQUIDACION_EMPLEADO;
SELECT * FROM ERROR_CALC;