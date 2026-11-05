CREATE TABLE customers (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    city TEXT NOT NULL,
    balance REAL NOT NULL
);
CREATE TABLE orders (
    id INTEGER PRIMARY KEY,
    customer_id INTEGER NOT NULL REFERENCES customers(id),
    product TEXT NOT NULL,
    total REAL NOT NULL
);
INSERT INTO customers VALUES
    (1, 'Anna Weber', 'Berlin', 245.50),
    (2, 'Ben Fischer', 'Hamburg', 89.90),
    (3, 'Clara König', 'Berlin', 420.00),
    (4, 'David Schmidt', 'München', 135.25),
    (5, 'Elif Yılmaz', 'Köln', 310.75),
    (6, 'Felix Braun', 'Hamburg', 67.00);
INSERT INTO orders VALUES
    (1, 1, 'Tastatur', 89.00),
    (2, 1, 'Monitor', 249.00),
    (3, 3, 'Kopfhörer', 129.00),
    (4, 5, 'Maus', 49.90),
    (5, 6, 'USB-Hub', 34.00);
