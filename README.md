# DevOps Assessment: Terraform + Database Reliability

AWS infrastructure designed in Terraform (`Internet → ALB → ECS/Fargate → RDS`), plus a
locally runnable PostgreSQL setup covering migrations, seed data, query optimisation, and
backup/restore.

**No AWS account is needed.** `init`, `validate` and `plan` all run offline.

```
db/migrations/      001_schema.sql, 002_indexes.sql
db/seed/            003_seed.sql  (100,000 bookings + 32,500 events)
scripts/            backup.sh, restore.sh, verify.sh
infra/bootstrap/    S3 state bucket + DynamoDB lock table (one-time)
infra/modules/      network, ecs, rds
infra/envs/         dev, prod  (separate variables, tfvars, backend, sizing)
.github/workflows/  terraform.yml  (plan on PRs, apply on merge/dispatch)
```

Requires Terraform >= 1.6 and Docker with Compose v2. Tested on Terraform 1.15.8,
Docker 29.7.2. No host PostgreSQL needed — `psql` runs inside the container.

---

## Part 1–2: Terraform

```bash
terraform fmt -check -recursive infra     # no output, exit 0

cd infra/envs/dev                         # then repeat in ../prod
terraform init
terraform validate                        # Success! The configuration is valid.
terraform plan -refresh=false             # dev: Plan: 36 to add / prod: 39 to add
```

`terraform.tfvars` is loaded automatically, so no `-var-file` flag is needed.

**Why this works with no credentials.** Each environment has a `backend_override.tf` that
switches state to the `local` backend (otherwise `init` fails reaching the S3 bucket), and
`plan_only = true` gives the AWS provider placeholder credentials so it never calls STS.
`backend.tf` still holds the real S3 remote-state config for each environment. To use a real
account, delete `backend_override.tf` and set `plan_only = false`.

### RDS is private and reachable only from ECS/Fargate

Three independent controls, all visible in the plan:

1. `publicly_accessible = false`.
2. The DB subnet group lists **only private subnets**, which have no route to the internet
   gateway.
3. The security group's only ingress rule references the ECS task security group **by ID**,
   not by CIDR:

   ```hcl
   referenced_security_group_id = var.ecs_security_group_id
   from_port                    = 5432
   ```

Point 3 is what makes it "only from ECS" — a CIDR rule for the private subnets would also
admit anything else placed there. The database has no egress rules at all. The master
password is never in the repo or state: `manage_master_user_password = true` has RDS generate
it into Secrets Manager.

### dev vs prod

Separate root modules, separate state, separate tfvars.

| | dev | prod |
|---|---|---|
| State key | `hotel-booking/dev/terraform.tfstate` | `hotel-booking/prod/terraform.tfstate` |
| VPC CIDR | `10.10.0.0/16` | `10.20.0.0/16` |
| NAT gateways | 1 (shared) | 1 per AZ |
| Fargate task | 256 CPU / 512 MiB, 1 task | 1024 CPU / 2048 MiB, 2 tasks |
| RDS instance | `db.t3.micro` | `db.t3.medium` |
| RDS storage | 20 GiB (max 50) | 100 GiB (max 500) |
| Multi-AZ | false | true |
| **Backup retention** | **3 days** | **30 days** |
| **Deletion protection** | **false** | **true** |
| Final snapshot | skipped | required |

To confirm these from the plan rather than this table:

```bash
terraform plan -refresh=false -no-color \
  | grep -E '^ +\+ (publicly_accessible|multi_az|backup_retention_period|deletion_protection|instance_class) ' \
  | sort -u
```

---

## Part 3: GitHub Actions

`.github/workflows/terraform.yml` has two jobs.

**`plan`** — on pull requests touching `infra/**`. A `dev`/`prod` matrix running `fmt -check`,
`init`, `validate` and `plan -refresh=false`. The plan is posted as a sticky PR comment (one
per environment, updated in place on re-runs) and uploaded as an artifact. No AWS credentials
and no remote state, so it also runs on forks and cannot change anything.

**`apply`** — pushes to `main` apply **dev**; **prod** is manual (Actions → Run workflow →
pick `prod`). It configures credentials, removes `backend_override.tf` so the real S3 backend
in `backend.tf` takes effect, runs a plain `terraform init`, plans, then applies **that saved
plan file** so what was planned is what runs.

### Remote state — required before any apply

`infra/bootstrap` creates the S3 bucket and DynamoDB lock table that
`infra/envs/*/backend.tf` point at. It is applied once, by hand:

```bash
cd infra/bootstrap
# edit terraform.tfvars: state_bucket_name must be globally unique
terraform init
terraform plan -refresh=false                 # 6 to add, works offline
terraform apply -var plan_only=false          # creates the bucket + table
```

`infra/envs/*/backend.tf` already name these resources
(`hotel-booking-tfstate-changeme` and `hotel-booking-terraform-lock`), so there is nothing to
wire up afterwards — **unless** you change `state_bucket_name`, in which case update `bucket`
in both `envs/dev/backend.tf` and `envs/prod/backend.tf` to match. S3 bucket names are global,
so the shipped name will collide and does need changing.

It creates a versioned, encrypted, non-public bucket (old state versions expire after 90
days) and a `PAY_PER_REQUEST` lock table keyed on `LockID`. It keeps **local** state on
purpose — Terraform cannot store state in the bucket it is still creating — and the bucket
carries `prevent_destroy`, since state is the only record of what exists in AWS.

Then per environment: put the real names in `backend.tf`, delete `backend_override.tf`, and
run `terraform init -migrate-state`.

### GitHub settings the apply job needs

| Kind | Name |
|---|---|
| Repository secrets | `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` |
| Environments | `dev` and `prod` — add required reviewers to `prod` for an approval gate |

That is the whole setup: the bucket and lock table are named in `backend.tf`, not passed in as
CI variables. If the bucket does not exist, `terraform init` fails in the job before anything
is planned or applied, so a missing backend cannot lead to an apply against throwaway local
state.

Static keys are the quickest setup; OIDC is better, because nothing long-lived is stored in
the repo. To switch, replace the two `aws-access-key-id`/`aws-secret-access-key` inputs with
`role-to-assume: ${{ vars.AWS_ROLE_ARN }}` and add `id-token: write` to `permissions`.

**Applying costs money** — roughly $70/mo for dev and $250+/mo for prod in `ap-south-1` (NAT
gateways, ALB, RDS, Fargate), billed until destroyed. prod also sets `deletion_protection`
and `alb_deletion_protection`, so destroying it means turning those off and applying that
change *first*.

---

## Part 4: Local database

### Start it

```bash
docker compose up -d
```

Migrations and seed run automatically on first start, in the order `001_schema.sql` →
`002_indexes.sql` → `003_seed.sql`. `up -d` returns before they finish, so wait ~3 seconds:

```bash
until docker compose exec -T postgres \
        psql -U app_user -d hotel_booking -c "SELECT count(*) FROM booking_events;" \
        >/dev/null 2>&1; do printf '.'; sleep 2; done; echo " ready"
```

Connection details are in [docker-compose.yml](docker-compose.yml): `localhost:5432`,
database `hotel_booking`, user `app_user`, password `app_password` (local-only credentials).

The init scripts only run on an **empty** data volume. To re-run them, or if you ever see
`relation "hotel_bookings" does not exist`, reset with
`docker compose down -v && docker compose up -d`.

### Verify

```bash
./scripts/verify.sh
```

Prints nine sections and exits 0: tables, seed coverage (`100000` bookings, `32500` events,
`10` cities, `5` orgs, `4` statuses), per-city and per-status counts, event types, the four
indexes, the target query result, and the query plan **with** and **without** the index.

---

## Part 5: Seed data and the index

`db/seed/003_seed.sql` seeds **100,000 bookings** and **32,500 events** across 10 cities,
5 organisations, 4 statuses and 500 hotels, with `created_at` spread over the last 365 days.
Values derive from the `generate_series` counter rather than `random()`, so the data is
identical on every machine. Events cover every 10th booking with a `booking_created` →
`payment_captured` → `booking_confirmed` sequence, plus `refund_issued` for a sample of
cancelled bookings, each with a JSONB payload.

The brief asks for at least 100 bookings; seeding far more is deliberate. On a 100-row table a
sequential scan is always the cheapest plan, so `EXPLAIN` would prove nothing. At 100,000 rows
the target query matches ~821 rows (~0.8%), where index selection becomes real.

### The index

```sql
CREATE INDEX idx_hotel_bookings_city_created_at
    ON hotel_bookings (city, created_at)
    INCLUDE (org_id, status, amount);
```

1. **`city` first** — the equality predicate (`city = 'delhi'`), which positions the scan on
   one contiguous range of the index.
2. **`created_at` second** — the range predicate. Because the equality column comes first, the
   date range is a prefix of that range and the scan stops early instead of reading all 10,000
   `delhi` rows. A range column is only useful *after* every equality column: `(created_at,
   city)` could not use the `city` equality to narrow the scan at all.
3. **`org_id`, `status`, `amount` as `INCLUDE` columns** — never filtered on, only grouped and
   aggregated, so they don't belong in the key. Carrying them as leaf-page payload lets
   PostgreSQL answer the query from the index alone, while keeping the key narrow.

A separate `(org_id, status)` index was deliberately not kept: `GROUP BY` runs *after* `WHERE`
has cut the set to ~821 rows, and hash-aggregating those is cheaper than any index could make
it, so it would only add write cost.

Measured by `./scripts/verify.sh`, sections 8 and 9 (section 9 disables index scans for one
session to show the unindexed cost):

| | Without index | With index |
|---|---|---|
| Plan | `Seq Scan` | **`Index Only Scan`** |
| Rows discarded by filter | 99,179 | 0 |
| Buffers read | 1,439 | **13** |
| Execution time | 5.286 ms | **0.214 ms** |

**≈25× faster, ≈110× fewer buffers**, and `Heap Fetches: 0` confirms the table is never read.

The seed ends with `VACUUM ANALYZE`, not just `ANALYZE`, for a reason: an index-only scan can
only skip the heap for pages marked all-visible in the visibility map, and a bulk `INSERT`
leaves that map unset. Without the `VACUUM` the planner picks a bitmap heap scan and re-reads
~473 heap blocks it doesn't need — the index is used, but the "index only" benefit is lost.

A second index, `idx_booking_events_booking_id_created_at`, serves a booking's event timeline
and keeps the `ON DELETE CASCADE` an index lookup rather than a scan.

---

## Part 6: Backup and restore

```bash
./scripts/backup.sh     # backups/hotel_booking_<UTC timestamp>.dump  (4.7 MB) + .dump.meta
./scripts/restore.sh    # restores into a fresh database, then verifies
```

`restore.sh` restores into a **new** database, `hotel_booking_restore`, leaving the original
untouched, and runs `pg_restore --exit-on-error` so failures are loud.

### How to verify the restore worked

`restore.sh` verifies itself and **exits non-zero if anything does not match**, so `echo $?`
is the short answer. It checks the dump's SHA-256 against the `.meta` sidecar written at
backup time, both row counts against the counts recorded then, that all 4 indexes and the
`booking_events` foreign key came back, and per-city totals. A successful run ends:

```
      table            expected     restored
      hotel_bookings   100000       100000
      booking_events   32500        32500

Restore verified successfully.
  indexes  : 4
```

To confirm independently, compare the two databases:

```bash
docker compose exec -T postgres psql -U app_user -d hotel_booking         -c "SELECT count(*) FROM hotel_bookings;"
docker compose exec -T postgres psql -U app_user -d hotel_booking_restore -c "SELECT count(*) FROM hotel_bookings;"
```

Or prove the backup can rebuild destroyed data:

```bash
./scripts/backup.sh
docker compose exec -T postgres psql -U app_user -d hotel_booking -c "TRUNCATE hotel_bookings CASCADE;"
./scripts/restore.sh          # restores 100000 / 32500, exit 0
```

The verification also fails when it should: tamper with a dump (`printf 'x' | dd of=... bs=1
seek=2000 conv=notrunc`) and `restore.sh` exits 1 with `checksum mismatch`.

### Tear down

```bash
docker compose down -v && rm -rf backups
```
