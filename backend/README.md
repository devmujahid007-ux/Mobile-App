# NeuroScan AI — FastAPI backend

Same API as the web NeuroScanAi project. Used by the Flutter app in this repo.

## Prerequisites

- Python 3.10+
- MySQL 8 (local install or Docker)

## Quick start (Windows, from `Mobile-app` repo root)

**With Docker Desktop** (MySQL in a container):

```powershell
.\setup_and_run_backend.ps1
```

**Without Docker** — install MySQL 8 locally, create database `tumer_db`, set passwords in `backend\.env`, then:

```powershell
.\setup_backend_no_docker.ps1
```

Until **http://127.0.0.1:8000/docs** loads in a browser, the Flutter app will always show connection / signup errors (`ERR_CONNECTION_REFUSED` means the API is not running).

If you only need to start the API again (venv already exists, MySQL already running):

```powershell
cd backend
.\venv\Scripts\Activate.ps1
uvicorn main:app --host 0.0.0.0 --port 8000
```

## Database (Docker)

From the **Mobile-app** repo root:

```bash
docker compose up -d
```

## Configuration

```bash
cd backend
copy .env.example .env
```

Edit `.env`: set `MYSQL_*` to match MySQL (defaults match `docker-compose.yml`: user `root`, password `admin`, database `tumer_db`, host `127.0.0.1`, port `3306`). Set a strong `JWT_SECRET` for production.

## Install and run

```bash
cd backend
python -m venv venv
venv\Scripts\activate
pip install -r requirements.txt
python create_tables.py
```

Optional superadmin (for `/users/` and admin tooling):

```bash
set SUPERADMIN_EMAIL=admin@example.com
set SUPERADMIN_PASSWORD=yourpassword
python create_tables.py
```

Start API (**must** use `--host 0.0.0.0` if the Flutter app uses your LAN IP like `http://192.168.x.x:8000`). Binding only to `127.0.0.1` will cause **“Failed to fetch”** / connection errors from other devices or from the same PC using the LAN address.

```bash
uvicorn main:app --host 0.0.0.0 --port 8000
```

From the **Mobile-app** repo root on Windows you can run:

```powershell
.\run_backend.ps1
```

**Windows Firewall:** allow inbound **TCP 8000** (or allow **Python**) so phones on Wi‑Fi can connect.

Docs: `http://127.0.0.1:8000/docs` — try the same URL with your IPv4 from `ipconfig` in a phone browser to verify the network path.

## Notes

- First startup loads ML weights; `/predict` and clinical analysis need those dependencies and GPU/CPU RAM as in the original project.
- Large `data/` outputs and `uploads/` are not committed; directories are created at runtime.
