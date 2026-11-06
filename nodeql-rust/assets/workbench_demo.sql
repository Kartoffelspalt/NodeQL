CREATE TABLE Customers (
    id INTEGER PRIMARY KEY,
    company_name TEXT NOT NULL,
    contact_name TEXT NOT NULL,
    email TEXT NOT NULL,
    country TEXT NOT NULL,
    industry TEXT NOT NULL,
    created_at TEXT NOT NULL
);
CREATE TABLE Orders (
    id INTEGER PRIMARY KEY,
    customer_id INTEGER NOT NULL REFERENCES Customers(id),
    status TEXT NOT NULL,
    created_at TEXT NOT NULL
);
INSERT INTO Customers VALUES
    (1, 'Vertex Solutions 1', 'Contact 1', 'contact1@example.com', 'UK', 'Technology', '2024-08-30T00:00:00'),
    (2, 'Prime Solutions 2', 'Contact 2', 'contact2@example.com', 'DE', 'Retail', '2024-09-02T00:00:00'),
    (3, 'Atlas Studio 3', 'Contact 3', 'contact3@example.com', 'FR', 'Design', '2024-09-08T00:00:00');
INSERT INTO Orders VALUES
    (778, 1, 'Pending', '2024-10-11T00:00:00'),
    (14010, 1, 'Shipped', '2023-07-21T00:00:00'),
    (16040, 1, 'Paid', '2023-10-03T00:00:00'),
    (19160, 1, 'Pending', '2023-02-01T00:00:00'),
    (19420, 2, 'Paid', '2024-11-01T00:00:00'),
    (19421, 2, 'Pending', '2024-11-02T00:00:00'),
    (19422, 2, 'Shipped', '2024-11-03T00:00:00'),
    (19423, 2, 'Paid', '2024-11-04T00:00:00'),
    (19424, 3, 'Pending', '2024-11-05T00:00:00'),
    (19425, 3, 'Shipped', '2024-11-06T00:00:00');
INSERT INTO Customers VALUES
    (4, 'Horizon Manufacturing 4', 'Contact 4', 'contact4@example.com', 'NL', 'Manufacturing', '2024-09-09T00:00:00');
INSERT INTO Orders VALUES
    (19426, 4, 'Paid', '2024-11-07T00:00:00');

CREATE TABLE Categories (id INTEGER PRIMARY KEY, name TEXT NOT NULL);
INSERT INTO Categories VALUES
    (1, 'Electronics'), (2, 'Office'), (3, 'Industrial'), (4, 'Medical'),
    (5, 'Networking'), (6, 'Cloud'), (7, 'Furniture'), (8, 'Software'),
    (9, 'Safety'), (10, 'Supplies');
CREATE TABLE Products (id INTEGER PRIMARY KEY, name TEXT NOT NULL, category_id INTEGER REFERENCES Categories(id), price REAL);
INSERT INTO Products VALUES (1, 'Monitor', 1, 249.00), (2, 'Office chair', 7, 179.00), (3, 'Network switch', 5, 99.00);
CREATE TABLE Warehouses (id INTEGER PRIMARY KEY, name TEXT NOT NULL, country TEXT);
INSERT INTO Warehouses VALUES (1, 'London', 'UK'), (2, 'Berlin', 'DE');
CREATE TABLE Inventory (product_id INTEGER REFERENCES Products(id), warehouse_id INTEGER REFERENCES Warehouses(id), quantity INTEGER);
INSERT INTO Inventory VALUES (1, 1, 25), (2, 1, 12), (3, 2, 40);
CREATE TABLE Invoices (id INTEGER PRIMARY KEY, order_id INTEGER REFERENCES Orders(id), total REAL);
INSERT INTO Invoices VALUES (1, 778, 249.00), (2, 14010, 179.00);
CREATE TABLE OrderItems (order_id INTEGER REFERENCES Orders(id), product_id INTEGER REFERENCES Products(id), quantity INTEGER);
INSERT INTO OrderItems VALUES (778, 1, 1), (14010, 2, 1), (16040, 3, 2);
