set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

task6-l0:
    python3 scripts/task6/run_stage_local.py --stage l0

task6-l1:
    python3 scripts/task6/run_stage_local.py --stage l1

task6-l2:
    python3 scripts/task6/run_stage_local.py --stage l2

task6-l3:
    python3 scripts/task6/run_stage_local.py --stage l3

task6-l4:
    python3 scripts/task6/run_stage_local.py --stage l4

task6-x1:
    python3 scripts/task6/run_stage_local.py --stage x1

task6-x2:
    python3 scripts/task6/run_stage_local.py --stage x2

task6-x3:
    python3 scripts/task6/run_stage_local.py --stage x3

