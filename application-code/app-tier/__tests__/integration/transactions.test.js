// Integration test: talks to a real Postgres instance.
// In CI this points at the "postgres" service container defined in the
// Jenkins pipeline; locally set DB_HOST/DB_USER/DB_PWD/DB_DATABASE env vars.
const transactionService = require('../../TransactionService');

describe('TransactionService (Postgres integration)', () => {
    beforeAll((done) => {
        transactionService.deleteAllTransactions(() => done());
    });

    it('adds and retrieves a transaction', (done) => {
        transactionService.addTransaction(42.5, 'integration test');
        setTimeout(() => {
            transactionService.getAllTransactions((rows) => {
                expect(rows.length).toBeGreaterThan(0);
                expect(Number(rows[0].amount)).toBeCloseTo(42.5);
                done();
            });
        }, 200);
    });
});
