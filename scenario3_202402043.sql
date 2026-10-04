CREATE TABLE hostel_rooms (
    room_id          SERIAL PRIMARY KEY,
    room_number      VARCHAR(10) NOT NULL UNIQUE,
    available_spaces INTEGER NOT NULL CHECK (available_spaces >= 0)
);

CREATE TABLE allocations (
    allocation_id   SERIAL PRIMARY KEY,
    student_number  VARCHAR(20) NOT NULL CHECK (TRIM(student_number) <> ''),
    room_id         INTEGER NOT NULL REFERENCES hostel_rooms(room_id),
    status          VARCHAR(20) NOT NULL DEFAULT 'ALLOCATED'
        CHECK (status IN ('ALLOCATED', 'COMPLETE'))
);
INSERT INTO hostel_rooms (room_number, available_spaces) VALUES
    ('A101', 4),
    ('A102', 1),
    ('B201', 0),
    ('B202', 3);
	SELECT * FROM hostel_rooms ORDER BY room_id;

DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN SELECT room_number, available_spaces FROM hostel_rooms ORDER BY room_id LOOP
        IF r.available_spaces = 0 THEN
            RAISE NOTICE 'Room %: % spaces - FULL', r.room_number, r.available_spaces;
        ELSIF r.available_spaces = 1 THEN
            RAISE NOTICE 'Room %: % space - ONE SPACE LEFT', r.room_number, r.available_spaces;
        ELSE
            RAISE NOTICE 'Room %: % spaces - SEVERAL SPACES available', r.room_number, r.available_spaces;
        END IF;
    END LOOP;
END;
$$;
DO $$
DECLARE
    i INTEGER := 1;
BEGIN
    -- WHILE loop: three hostel inspection days
    WHILE i <= 3 LOOP
        RAISE NOTICE 'Hostel inspection day %', i;
        i := i + 1;
    END LOOP;

    -- Numeric FOR loop: three room checks
    FOR n IN 1..3 LOOP
        RAISE NOTICE 'Room check number %', n;
    END LOOP;
END;
$$;


CREATE OR REPLACE PROCEDURE allocate_room(
    p_student_number VARCHAR,
    p_room_id        INTEGER
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_available INTEGER;
BEGIN
    IF p_student_number IS NULL OR TRIM(p_student_number) = '' THEN
        RAISE EXCEPTION 'Invalid input: student number cannot be blank';
    END IF;

    SELECT available_spaces INTO v_available
    FROM hostel_rooms
    WHERE room_id = p_room_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Room % does not exist', p_room_id;
    END IF;

    IF v_available <= 0 THEN
        RAISE EXCEPTION 'Room % is full: no bed space available', p_room_id;
    END IF;

    UPDATE hostel_rooms
    SET available_spaces = available_spaces - 1
    WHERE room_id = p_room_id;

    INSERT INTO allocations (student_number, room_id, status)
    VALUES (TRIM(p_student_number), p_room_id, 'ALLOCATED');

    RAISE NOTICE 'SUCCESS: student % allocated to room %', p_student_number, p_room_id;
END;
$$;

DO $$
BEGIN
    CALL allocate_room('2024001', 1);   -- valid (room A101)
    CALL allocate_room('2024002', 2);   -- valid (room A102 - takes its last space)
END;
$$;

DO $$
BEGIN
    CALL allocate_room('2024003', 3);   -- room B201 is full
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'REJECTED: %', SQLERRM;
END;
$$;


SELECT * FROM hostel_rooms ORDER BY room_id;
SELECT * FROM allocations ORDER BY allocation_id;


CREATE OR REPLACE PROCEDURE check_out(p_allocation_id INTEGER)
LANGUAGE plpgsql
AS $$
DECLARE
    v_room_id INTEGER;
    v_status  VARCHAR(20);
BEGIN
    SELECT room_id, status INTO v_room_id, v_status
    FROM allocations
    WHERE allocation_id = p_allocation_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Allocation % does not exist', p_allocation_id;
    END IF;

    IF v_status = 'COMPLETE' THEN
        RAISE NOTICE 'Allocation % is already COMPLETE. No extra space freed.', p_allocation_id;
        RETURN;
    END IF;

    UPDATE hostel_rooms
    SET available_spaces = available_spaces + 1
    WHERE room_id = v_room_id;

    UPDATE allocations
    SET status = 'COMPLETE'
    WHERE allocation_id = p_allocation_id;

    RAISE NOTICE 'Allocation % checked out. One bed space released.', p_allocation_id;
END;
$$;


SELECT * FROM hostel_rooms ORDER BY room_id;
SELECT * FROM allocations ORDER BY allocation_id;
DO $$
DECLARE
    cur_rooms CURSOR FOR
        SELECT room_id, room_number, available_spaces
        FROM hostel_rooms
        WHERE available_spaces <= 1
        ORDER BY available_spaces, room_id;
    v_id     INTEGER;
    v_number VARCHAR;
    v_spaces INTEGER;
BEGIN
    OPEN cur_rooms;
    LOOP
        FETCH cur_rooms INTO v_id, v_number, v_spaces;
        EXIT WHEN NOT FOUND;
        IF v_spaces = 0 THEN
            RAISE NOTICE 'Room % (id %): FULL', v_number, v_id;
        ELSE
            RAISE NOTICE 'Room % (id %): NEARLY FULL - % space left', v_number, v_id, v_spaces;
        END IF;
    END LOOP;
    CLOSE cur_rooms;
END;
$$;


DO $$
BEGIN
    CALL allocate_room('   ', 4);
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Invalid input handled: %', SQLERRM;
END;
$$;

SELECT * FROM hostel_rooms ORDER BY room_id;
SELECT * FROM allocations ORDER BY allocation_id;

