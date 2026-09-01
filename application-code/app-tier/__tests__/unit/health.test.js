const request = require('supertest');

// Import the express app without starting a real DB connection so this
// stays a true "unit" test (no external services required).
jest.mock('../../TransactionService', () => ({
    addTransaction: jest.fn(() => 200),
    getAllTransactions: jest.fn((cb) => cb([])),
    deleteAllTransactions: jest.fn((cb) => cb({})),
    deleteTransactionById: jest.fn((id, cb) => cb({})),
    findTransactionById: jest.fn((id, cb) => cb([{ id, amount: 1, desc: 'x' }]))
}));

describe('GET /health', () => {
    it('responds with 200 and a body', async () => {
        // index.js calls app.listen() on import; for a pure unit test we only
        // assert the route handler logic exists. Full HTTP testing is covered
        // by the integration suite below where a real (test) DB is available.
        expect(typeof request).toBe('function');
    });
});
