CREATE TABLE lab_sessions (
    session_id  SERIAL PRIMARY KEY,
    session_name  VARCHAR(100) NOT NULL,
    available_workstations  INTEGER NOT NULL CHECK (available_workstations >= 0)
);
CREATE TABLE reservations (
    reservation_id  SERIAL PRIMARY KEY,
    session_id  INTEGER NOT NULL REFERENCES lab_sessions(session_id),
    lecturer  VARCHAR(100) NOT NULL,
    workstations  INTEGER NOT NULL CHECK (workstations > 0),
    status  VARCHAR(20) NOT NULL DEFAULT 'RESERVED'
        CHECK (status IN ('RESERVED', 'CANCELLED'))
);
INSERT INTO lab_sessions (session_name, available_workstations) VALUES
    ('Mon 08:00 Programming Lab', 40),
    ('Tue 10:00 Networking Lab', 4),
    ('Wed 14:00 Database Lab', 0),
    ('Thu 09:00 Web Development Lab', 20);
SELECT * FROM lab_sessions ORDER BY session_id;
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN SELECT session_name, available_workstations FROM lab_sessions ORDER BY session_id LOOP
        IF r.available_workstations = 0 THEN
            RAISE NOTICE '%: % - FULL (no workstations left)', r.session_name, r.available_workstations;
        ELSIF r.available_workstations <= 5 THEN
            RAISE NOTICE '%: % - NEARLY FULL', r.session_name, r.available_workstations;
        ELSE
            RAISE NOTICE '%: % - enough workstations available', r.session_name, r.available_workstations;
        END IF;
    END LOOP;
END;
$$;

DO $$
DECLARE
    i INTEGER := 1;
BEGIN
    -- WHILE loop: three session preparation reminders
    WHILE i <= 3 LOOP
        RAISE NOTICE 'Session preparation reminder %', i;
        i := i + 1;
    END LOOP;

    -- Numeric FOR loop: three workstation checks
    FOR n IN 1..3 LOOP
        RAISE NOTICE 'Workstation check number %', n;
    END LOOP;
END;
$$;
CREATE OR REPLACE PROCEDURE reserve_workstations(
    p_session_id   INTEGER,
    p_lecturer  VARCHAR,
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
    SELECT available_workstations INTO v_available
    FROM lab_sessions
    WHERE session_id = p_session_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Session % does not exist', p_session_id;
    END IF;

    IF v_available < p_qty THEN
        RAISE EXCEPTION 'Insufficient stock for session %: requested %, available %',
            p_session_id, p_qty, v_available;
    END IF;

    UPDATE lab_sessions
    SET available_workstations = available_workstations - p_qty
    WHERE session_id = p_session_id;

    INSERT INTO reservations (session_id, lecturer, workstations, status)
    VALUES (p_session_id, p_lecturer, p_qty, 'RESERVED');

    RAISE NOTICE 'SUCCESS: % unit(s) of session % recorded for %',
        p_qty, p_session_id, p_lecturer;
END;
$$;
DO $$
BEGIN
    CALL reserve_workstations(1, 'Dr. Banda', 10);   -- valid
    CALL reserve_workstations(2, 'Mr. Phiri', 2);   -- valid
END;
$$;

DO $$
BEGIN
    CALL reserve_workstations(1, 'Ms. Zulu', 50);   -- exceeds available stock
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'REJECTED: %', SQLERRM;
END;
$$;
SELECT * FROM lab_sessions ORDER BY session_id;
SELECT * FROM reservations ORDER BY reservation_id;
CREATE OR REPLACE PROCEDURE cancel_reservation(p_reservation_id INTEGER)
LANGUAGE plpgsql
AS $$
DECLARE
    v_session_id  INTEGER;
    v_qty     INTEGER;
    v_status  VARCHAR(20);
BEGIN
    SELECT session_id, workstations, status
    INTO v_session_id, v_qty, v_status
    FROM reservations
    WHERE reservation_id = p_reservation_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Record % does not exist', p_reservation_id;
    END IF;

    IF v_status = 'CANCELLED' THEN
        RAISE NOTICE 'Record % is already CANCELLED. Stock NOT restored again.', p_reservation_id;
        RETURN;
    END IF;

    UPDATE lab_sessions
    SET available_workstations = available_workstations + v_qty
    WHERE session_id = v_session_id;

    UPDATE reservations
    SET status = 'CANCELLED'
    WHERE reservation_id = p_reservation_id;

    RAISE NOTICE 'Record % marked CANCELLED. % unit(s) restored.', p_reservation_id, v_qty;
END;
$$;
SELECT * FROM lab_sessions ORDER BY session_id;
SELECT * FROM reservations ORDER BY reservation_id;
DO $$
DECLARE
    cur_low CURSOR FOR
        SELECT session_id, session_name, available_workstations
        FROM lab_sessions
        WHERE available_workstations <= 5
        ORDER BY available_workstations, session_id;
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
    CALL reserve_workstations(1, 'Dr. Mumba', 0);
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Invalid request handled: %', SQLERRM;
END;
$$;

SELECT * FROM lab_sessions ORDER BY session_id;
SELECT * FROM reservations ORDER BY reservation_id;


