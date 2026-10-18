"""Employee Recruitment System - Flask backend + MySQL (REST API + static frontend)."""
import datetime, decimal, sys
import mysql.connector
from flask import Flask, jsonify, request, g
from werkzeug.exceptions import HTTPException

# ====== EDIT THESE TO MATCH YOUR MYSQL ======
DB_CONFIG = dict(
    host="localhost",
    port=3306,
    user="root",
    password="your_password_here",   # <- your MySQL Workbench / root password
    database="recruitment_db",
)
# ============================================

app = Flask(__name__, static_folder="static", static_url_path="")

# entity -> (table, primary key, writable columns, view used for listing)
ENTITIES = {
    "department":    ("department",    "dept_id",        ["name"], "department"),
    "vacancy":       ("vacancy",       "vacancy_id",     ["title","dept_id","openings","salary","min_experience","last_date","status"], "v_vacancy"),
    "applicant":     ("applicant",     "applicant_id",   ["name","email","phone","experience_years","address"], "applicant"),
    "qualification": ("qualification", "qual_id",        ["applicant_id","degree","institution","year","percentage"], "v_qualification"),
    "interviewer":   ("interviewer",   "interviewer_id", ["name","designation","dept_id"], "v_interviewer"),
    "application":   ("application",   "application_id", ["applicant_id","vacancy_id","applied_on","status"], "v_application"),
    "interview":     ("interview",     "interview_id",   ["application_id","interviewer_id","interview_date","round","score","remarks"], "v_interview"),
    "selection":     ("selection",     "selection_id",   ["application_id","decision","offered_salary","joining_date","decided_on"], "v_selection"),
}

def bt(c):  # backtick-quote column names (year / round are MySQL keywords)
    return f"`{c}`"

def db():
    if "db" not in g:
        g.db = mysql.connector.connect(**DB_CONFIG)
    return g.db

@app.teardown_appcontext
def close_db(_):
    con = g.pop("db", None)
    if con is not None and con.is_connected():
        con.close()

def norm(v):
    if isinstance(v, (datetime.date, datetime.datetime)): return v.isoformat()[:10]
    if isinstance(v, decimal.Decimal): return float(v)
    return v

def run(sql, args=(), write=False):
    con = db()
    cur = con.cursor(dictionary=True)
    try:
        cur.execute(sql, args)
        rows = [{k: norm(v) for k, v in r.items()} for r in cur.fetchall()] if cur.with_rows else []
        last = cur.lastrowid
        if write: con.commit()
        return rows, last
    except Exception:
        con.rollback()
        raise
    finally:
        cur.close()

def clean(cols, data):
    # empty strings -> NULL so optional columns behave
    return {c: (None if data.get(c) in ("", None) else data[c]) for c in cols if c in data}

@app.errorhandler(Exception)
def any_error(e):
    if isinstance(e, HTTPException): return e
    if isinstance(e, mysql.connector.Error):
        n, msg = getattr(e, "errno", None), getattr(e, "msg", str(e))
        if n == 1062: msg = "Duplicate entry - this record already exists."
        elif n in (1451, 1452): msg = "Invalid reference, or the record is in use by other records."
        elif n == 3819: msg = "A value is outside the allowed range."
        elif n in (1048, 1264, 1265, 1292, 1366): msg = "A required value is missing or invalid."
        elif n == 1644: pass  # our own trigger message (closed vacancy / experience)
        elif n in (1045, 1049, 2003): msg = f"Cannot connect to MySQL: {msg}"
        return jsonify(error=msg), 400
    app.logger.exception(e)
    return jsonify(error=f"Server error: {e}"), 500

@app.get("/")
def home(): return app.send_static_file("index.html")

@app.get("/api/<name>")
def list_(name):
    if name not in ENTITIES: return jsonify(error="Unknown entity"), 404
    _, pk, _, view = ENTITIES[name]
    rows, _ = run(f"SELECT * FROM {view} ORDER BY {pk} DESC")
    return jsonify(rows)

@app.post("/api/<name>")
def create(name):
    if name not in ENTITIES: return jsonify(error="Unknown entity"), 404
    table, pk, cols, _ = ENTITIES[name]
    d = clean(cols, request.get_json(force=True))
    sql = f"INSERT INTO {table} ({','.join(map(bt, d))}) VALUES ({','.join(['%s']*len(d))})"
    _, new_id = run(sql, list(d.values()), write=True)
    return jsonify(id=new_id), 201

@app.put("/api/<name>/<int:id_>")
def update(name, id_):
    if name not in ENTITIES: return jsonify(error="Unknown entity"), 404
    table, pk, cols, _ = ENTITIES[name]
    d = clean(cols, request.get_json(force=True))
    sets = ",".join(f"{bt(c)}=%s" for c in d)
    run(f"UPDATE {table} SET {sets} WHERE {pk}=%s", [*d.values(), id_], write=True)
    return jsonify(ok=True)

@app.delete("/api/<name>/<int:id_>")
def delete(name, id_):
    if name not in ENTITIES: return jsonify(error="Unknown entity"), 404
    table, pk, _, _ = ENTITIES[name]
    run(f"DELETE FROM {table} WHERE {pk}=%s", (id_,), write=True)
    return jsonify(ok=True)

@app.get("/api/report/stats")
def stats():
    one = lambda s: next(iter(run(s)[0][0].values()))
    q = lambda s: run(s)[0]
    return jsonify(
        counts={t: one(f"SELECT COUNT(*) AS c FROM {t}") for t in
                ("vacancy","applicant","application","interview","selection")},
        open_vacancies=one("SELECT COUNT(*) AS c FROM vacancy WHERE status='Open'"),
        by_status=q("SELECT status, COUNT(*) AS n FROM application GROUP BY status"),
        ranking=q("SELECT * FROM v_ranking LIMIT 10"),
        per_vacancy=q("SELECT title, department, openings, applications, filled FROM v_vacancy"),
    )

if __name__ == "__main__":
    try:
        mysql.connector.connect(**DB_CONFIG).close()
        print("Connected to MySQL database:", DB_CONFIG["database"])
    except mysql.connector.Error as e:
        print("\nCould not connect to MySQL:", e)
        print("1) Is MySQL running?  2) Did you run recruitment_db.sql in Workbench?  3) Is the password in app.py correct?")
        sys.exit(1)
    app.run(debug=False)
