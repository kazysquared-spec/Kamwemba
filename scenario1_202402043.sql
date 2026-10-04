CREATE TABLE books (
    book_id  SERIAL PRIMARY KEY,
    title  VARCHAR(100) NOT NULL,
    available_copies  INTEGER NOT NULL CHECK (available_copies >= 0)
);
CREATE TABLE book_loans (
    loan_id  SERIAL PRIMARY KEY,
    book_id  INTEGER NOT NULL REFERENCES books(book_id),
    student_number  VARCHAR(100) NOT NULL,
    quantity  INTEGER NOT NULL CHECK (quantity > 0),
    loan_status  VARCHAR(20) NOT NULL DEFAULT 'BORROWED'
        CHECK (loan_status IN ('BORROWED', 'RETURNED'))
);
INSERT INTO books (title, available_copies) VALUES
    ('Database Systems', 5),
    ('Operating Systems', 2),
    ('Computer Networks', 0),
    ('Software Engineering', 10);

SELECT * FROM books ORDER BY book_id;
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN SELECT title, available_copies FROM books ORDER BY book_id LOOP
        IF r.available_copies = 0 THEN
            RAISE NOTICE '%: % - UNAVAILABLE (no copies left)', r.title, r.available_copies;
        ELSIF r.available_copies <= 3 THEN
            RAISE NOTICE '%: % - LOW on copies', r.title, r.available_copies;
        ELSE
            RAISE NOTICE '%: % - sufficiently stocked', r.title, r.available_copies;
        END IF;
    END LOOP;
END;
$$;
DO $$
DECLARE
    i INTEGER := 1;
BEGIN
    -- WHILE loop: three overdue reminder numbers
    WHILE i <= 3 LOOP
        RAISE NOTICE 'Overdue reminder number %', i;
        i := i + 1;
    END LOOP;

    -- Numeric FOR loop: three library shelf numbers
    FOR n IN 1..3 LOOP
        RAISE NOTICE 'Library shelf number %', n;
    END LOOP;
END;
$$;
CREATE OR REPLACE PROCEDURE borrow_book(
    p_book_id   INTEGER,
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
    SELECT available_copies INTO v_available
    FROM books
    WHERE book_id = p_book_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Book % does not exist', p_book_id;
    END IF;

    IF v_available < p_qty THEN
        RAISE EXCEPTION 'Insufficient stock for book %: requested %, available %',
            p_book_id, p_qty, v_available;
    END IF;

    UPDATE books
    SET available_copies = available_copies - p_qty
    WHERE book_id = p_book_id;

    INSERT INTO book_loans (book_id, student_number, quantity, loan_status)
    VALUES (p_book_id, p_student_number, p_qty, 'BORROWED');

    RAISE NOTICE 'SUCCESS: % unit(s) of book % recorded for %',
        p_qty, p_book_id, p_student_number;
END;
$$;
DO $$
BEGIN
    CALL borrow_book(1, '2024001', 2);   -- valid
    CALL borrow_book(2, '2024002', 1);   -- valid
END;
$$;

DO $$
BEGIN
    CALL borrow_book(1, '2024003', 10);   -- exceeds available stock
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'REJECTED: %', SQLERRM;
END;
$$;
SELECT * FROM books ORDER BY book_id;
SELECT * FROM book_loans ORDER BY loan_id;
CREATE OR REPLACE PROCEDURE return_book(p_loan_id INTEGER)
LANGUAGE plpgsql
AS $$
DECLARE
    v_book_id  INTEGER;
    v_qty     INTEGER;
    v_status  VARCHAR(20);
BEGIN
    SELECT book_id, quantity, loan_status
    INTO v_book_id, v_qty, v_status
    FROM book_loans
    WHERE loan_id = p_loan_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Record % does not exist', p_loan_id;
    END IF;

    IF v_status = 'RETURNED' THEN
        RAISE NOTICE 'Record % is already RETURNED. Stock NOT restored again.', p_loan_id;
        RETURN;
    END IF;

    UPDATE books
    SET available_copies = available_copies + v_qty
    WHERE book_id = v_book_id;

    UPDATE book_loans
    SET loan_status = 'RETURNED'
    WHERE loan_id = p_loan_id;

    RAISE NOTICE 'Record % marked RETURNED. % unit(s) restored.', p_loan_id, v_qty;
END;
$$
SELECT * FROM books ORDER BY book_id;
SELECT * FROM book_loans ORDER BY loan_id;
DO $$
DECLARE
    cur_low CURSOR FOR
        SELECT book_id, title, available_copies
        FROM books
        WHERE available_copies <= 3
        ORDER BY available_copies, book_id;
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
    CALL borrow_book(1, '2024004', 0);
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Invalid request handled: %', SQLERRM;
END;
$$;
SELECT * FROM books ORDER BY book_id;
SELECT * FROM book_loans ORDER BY loan_id;



