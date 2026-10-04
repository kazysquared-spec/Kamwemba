CREATE TABLE medicines (
    medicine_id  SERIAL PRIMARY KEY,
    medicine_name  VARCHAR(100) NOT NULL,
    stock_quantity  INTEGER NOT NULL CHECK (stock_quantity >= 0)
);
CREATE TABLE dispensing_records (
    record_id  SERIAL PRIMARY KEY,
    medicine_id  INTEGER NOT NULL REFERENCES medicines(medicine_id),
    student_number  VARCHAR(100) NOT NULL,
    quantity  INTEGER NOT NULL CHECK (quantity > 0),
    status  VARCHAR(20) NOT NULL DEFAULT 'DISPENSED'
        CHECK (status IN ('DISPENSED', 'REVERSED'))
);



INSERT INTO medicines (medicine_name, stock_quantity) VALUES
    ('Paracetamol 500mg', 200),
    ('Amoxicillin 250mg', 15),
    ('Ibuprofen 400mg', 0),
    ('Oral Rehydration Salts', 60);


SELECT * FROM medicines ORDER BY medicine_id;

DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN SELECT medicine_name, stock_quantity FROM medicines ORDER BY medicine_id LOOP
        IF r.stock_quantity = 0 THEN
            RAISE NOTICE '%: % - OUT OF STOCK', r.medicine_name, r.stock_quantity;
        ELSIF r.stock_quantity <= 20 THEN
            RAISE NOTICE '%: % - LOW on stock', r.medicine_name, r.stock_quantity;
        ELSE
            RAISE NOTICE '%: % - sufficiently stocked', r.medicine_name, r.stock_quantity;
        END IF;
    END LOOP;
END;
$$;

DO $$
DECLARE
    i INTEGER := 1;
BEGIN
    -- WHILE loop: three stock review days
    WHILE i <= 3 LOOP
        RAISE NOTICE 'Stock review day %', i;
        i := i + 1;
    END LOOP;

    -- Numeric FOR loop: three shelf inspections
    FOR n IN 1..3 LOOP
        RAISE NOTICE 'Shelf inspection number %', n;
    END LOOP;
END;
$$;

CREATE OR REPLACE PROCEDURE dispense_medicine(
    p_medicine_id   INTEGER,
    p_student_number  VARCHAR,
    p_qty    INTEGER
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_available INTEGER;
BEGIN
    IF p_qty IS NULL OR p_qty <= 0 THEN
        RAISE EXCEPTION 'Invalid quantity: % (must be greater than zero)', p_qty;
    END IF;

    -- Lock the row so two users cannot take the same stock at once
    SELECT stock_quantity INTO v_available
    FROM medicines
    WHERE medicine_id = p_medicine_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Medicine % does not exist', p_medicine_id;
    END IF;

    IF v_available < p_qty THEN
        RAISE EXCEPTION 'Insufficient stock for medicine %: requested %, available %',
            p_medicine_id, p_qty, v_available;
    END IF;

    UPDATE medicines
    SET stock_quantity = stock_quantity - p_qty
    WHERE medicine_id = p_medicine_id;

    INSERT INTO dispensing_records (medicine_id, student_number, quantity, status)
    VALUES (p_medicine_id, p_student_number, p_qty, 'DISPENSED');

    RAISE NOTICE 'SUCCESS: % unit(s) of medicine % recorded for %',
        p_qty, p_medicine_id, p_student_number;
END;
$$;

DO $$
BEGIN
    CALL dispense_medicine(1, '2024001', 30);   -- valid
    CALL dispense_medicine(2, '2024002', 5);   -- valid
END;
$$;

DO $$
BEGIN
    CALL dispense_medicine(2, '2024003', 100);   -- exceeds available stock
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'REJECTED: %', SQLERRM;
END;
$$;
SELECT * FROM medicines ORDER BY medicine_id;
SELECT * FROM dispensing_records ORDER BY record_id;

CREATE OR REPLACE PROCEDURE reverse_dispensing(p_record_id INTEGER)
LANGUAGE plpgsql
AS $$
DECLARE
    v_medicine_id  INTEGER;
    v_qty     INTEGER;
    v_status  VARCHAR(20);
BEGIN
    SELECT medicine_id, quantity, status
    INTO v_medicine_id, v_qty, v_status
    FROM dispensing_records
    WHERE record_id = p_record_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Record % does not exist', p_record_id;
    END IF;

    IF v_status = 'REVERSED' THEN
        RAISE NOTICE 'Record % is already REVERSED. Stock NOT restored again.', p_record_id;
        RETURN;
    END IF;

    UPDATE medicines
    SET stock_quantity = stock_quantity + v_qty
    WHERE medicine_id = v_medicine_id;

    UPDATE dispensing_records
    SET status = 'REVERSED'
    WHERE record_id = p_record_id;

    RAISE NOTICE 'Record % marked REVERSED. % unit(s) restored.', p_record_id, v_qty;
END;
$$;

SELECT * FROM medicines ORDER BY medicine_id;
SELECT * FROM dispensing_records ORDER BY record_id;

DO $$
DECLARE
    cur_low CURSOR FOR
        SELECT medicine_id, medicine_name, stock_quantity
        FROM medicines
        WHERE stock_quantity <= 19
        ORDER BY stock_quantity, medicine_id;
    v_id   INTEGER;
    v_name VARCHAR;
    v_qty  INTEGER;
BEGIN
    OPEN cur_low;
    LOOP
        FETCH cur_low INTO v_id, v_name, v_qty;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE 'ID %: % - only % remaining', v_id, v_name, v_qty;
    END LOOP;
    CLOSE cur_low;
END;
$$;

DO $$
BEGIN
    CALL dispense_medicine(1, '2024004', -5);
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Invalid request handled: %', SQLERRM;
END;
$$;

SELECT * FROM medicines ORDER BY medicine_id;
SELECT * FROM dispensing_records ORDER BY record_id;

