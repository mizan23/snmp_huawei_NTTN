#!/usr/bin/env bash
set -e

echo "=== Bootstrap Python 3.10 + SNMP Trap Receiver ==="

# ---------------- CONFIG ----------------
PYTHON_VERSION="3.10.14"
PYTHON_TGZ="Python-${PYTHON_VERSION}.tgz"
PYTHON_SRC="/usr/src/Python-${PYTHON_VERSION}"
PYTHON_BIN="/usr/local/bin/python3.10"

VENV_DIR="$HOME/venv"
PROJECT_DIR="$HOME/snmp"
TRAP_SCRIPT="pysnmp_trap_receiver.py"

# ---------------- STEP 1: SYSTEM DEPS ----------------
echo "[1/7] Installing system dependencies..."
sudo apt update
sudo apt install -y \
  build-essential \
  libssl-dev \
  zlib1g-dev \
  libncurses5-dev \
  libncursesw5-dev \
  libreadline-dev \
  libsqlite3-dev \
  libgdbm-dev \
  libdb5.3-dev \
  libbz2-dev \
  libexpat1-dev \
  liblzma-dev \
  tk-dev \
  libffi-dev \
  uuid-dev \
  libpq-dev \
  curl

# ---------------- STEP 2: PYTHON 3.10 ----------------
if [ ! -x "$PYTHON_BIN" ]; then
  echo "[2/7] Installing Python ${PYTHON_VERSION} from source..."
  cd /usr/src
  sudo curl -O https://www.python.org/ftp/python/${PYTHON_VERSION}/${PYTHON_TGZ}
  sudo tar xzf ${PYTHON_TGZ}
  cd ${PYTHON_SRC}
  sudo ./configure --enable-optimizations
  sudo make -j$(nproc)
  sudo make altinstall
else
  echo "[2/7] Python 3.10 already installed"
fi

# ---------------- STEP 3: VERIFY PYTHON ----------------
echo "[3/7] Verifying Python..."
$PYTHON_BIN --version

# ---------------- STEP 4: VENV ----------------
if [ ! -d "$VENV_DIR" ]; then
  echo "[4/7] Creating virtual environment..."
  $PYTHON_BIN -m venv "$VENV_DIR"
fi

echo "Activating virtual environment..."
source "$VENV_DIR/bin/activate"

# ---------------- STEP 5: PIP ----------------
echo "[5/7] Upgrading pip..."
pip install --upgrade pip

# ---------------- STEP 6: PYTHON PACKAGES ----------------
echo "[6/7] Installing pinned Python dependencies..."
pip install \
  psycopg2-binary==2.9.11 \
  pyasn1==0.4.8 \
  pysnmp==4.4.12

# ---------------- STEP 7: VERIFY + RUN ----------------
echo "[7/7] Verifying imports..."
python - <<EOF
from pysnmp.entity import engine, config
import psycopg2
print("✔ pysnmp OK")
print("✔ psycopg2 OK")
EOF

