# grovs-railway

Wrapper images for deploying [Grovs](https://github.com/grovs-io) (open-source deep linking, attribution and referrals) on Railway.
The Railway template that uses them is published from the railwaytemplate2 pipeline. Roles: app (API, Sidekiq workers and a
Host-rewriting gateway), db (PostgreSQL 16), redis (Redis 7), clickhouse (ClickHouse 25.3), dashboard (Next.js dashboard).
