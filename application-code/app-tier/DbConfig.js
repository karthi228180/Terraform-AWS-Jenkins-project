// DB configuration is now sourced from environment variables instead of
// being hardcoded, so credentials never live in source control.
// SSL is on by default -- required by most managed Postgres services
// (RDS, Cloud SQL, etc.) and safe to leave on for local dev with self-signed certs.
module.exports = Object.freeze({
    DB_HOST: process.env.DB_HOST || 'localhost',
    DB_PORT: process.env.DB_PORT || 5432,
    DB_USER: process.env.DB_USER || 'postgres',
    DB_PWD: process.env.DB_PWD || '',
    DB_DATABASE: process.env.DB_DATABASE || 'webappdb',
    DB_SSL: process.env.DB_SSL !== 'false'
});
