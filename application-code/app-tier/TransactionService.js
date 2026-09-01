const dbcreds = require('./DbConfig');
const { Pool } = require('pg');

// A connection pool is safer and more efficient under load than the single
// long-lived connection the original mysql2 code used.
const pool = new Pool({
    host: dbcreds.DB_HOST,
    port: dbcreds.DB_PORT,
    user: dbcreds.DB_USER,
    password: dbcreds.DB_PWD,
    database: dbcreds.DB_DATABASE,
    ssl: dbcreds.DB_SSL ? { rejectUnauthorized: false } : false
});

pool.on('error', (err) => {
    // Prevents an idle client error from crashing the whole process.
    console.error('Unexpected error on idle Postgres client', err);
});

function addTransaction(amount, desc, callback) {
    // Parameterized query ($1, $2) -- values are never concatenated into the
    // SQL string, unlike the original template-literal version, which was
    // vulnerable to SQL injection.
    const query = 'INSERT INTO transactions (amount, description) VALUES ($1, $2)';
    pool.query(query, [amount, desc], (err, result) => {
        if (err) {
            console.error('Error adding transaction:', err.message);
            if (callback) return callback(err);
            return;
        }
        console.log('Adding to the table should have worked');
        if (callback) callback(null, result);
    });
    return 200;
}

function getAllTransactions(callback) {
    const query = 'SELECT * FROM transactions';
    pool.query(query, (err, result) => {
        if (err) {
            console.error('Error getting transactions:', err.message);
            return callback([], err);
        }
        console.log('Getting all transactions...');
        return callback(result.rows);
    });
}

function findTransactionById(id, callback) {
    const query = 'SELECT * FROM transactions WHERE id = $1';
    pool.query(query, [id], (err, result) => {
        if (err) {
            console.error('Error retrieving transaction:', err.message);
            return callback([], err);
        }
        console.log(`retrieving transactions with id ${id}`);
        return callback(result.rows);
    });
}

function deleteAllTransactions(callback) {
    const query = 'DELETE FROM transactions';
    pool.query(query, (err, result) => {
        if (err) {
            console.error('Error deleting transactions:', err.message);
            return callback(null, err);
        }
        console.log('Deleting all transactions...');
        return callback(result);
    });
}

function deleteTransactionById(id, callback) {
    const query = 'DELETE FROM transactions WHERE id = $1';
    pool.query(query, [id], (err, result) => {
        if (err) {
            console.error('Error deleting transaction:', err.message);
            return callback(null, err);
        }
        console.log(`Deleting transactions with id ${id}`);
        return callback(result);
    });
}

module.exports = {
    addTransaction,
    getAllTransactions,
    deleteAllTransactions,
    findTransactionById,
    deleteTransactionById
};
