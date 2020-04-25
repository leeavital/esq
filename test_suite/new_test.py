#!/usr/bin/env python3

import os
import subprocess
from os.path import dirname, join
from pathlib import Path

test_path = dirname(__file__)
parent = str(Path(test_path).absolute().parent)

higest_test = 0
for path in os.listdir(test_path):
    parts = path.split("_")
    if len(parts) == 1 or not parts[0].isnumeric():
        continue

    higest_test = max(int(parts[0]),  higest_test)


test_to_create =  higest_test + 1

print("input a test name (lowercase, underscore separated)")
test_name = input()

print("input a query")
query = input()

test_folder_name =  "%03d_%s" % (test_to_create, test_name)
test_folder_path = join(test_path, test_folder_name)
script_path = join(test_path, test_folder_name, "command.sh")
expect_stdout_path = join(test_path, test_folder_name, "expected.out")
expect_stderr_path = join(test_path, test_folder_name, "expected.err")

print(test_folder_path)
try:
    os.mkdir(test_folder_path)
except FileExistsError as e:
    print('exists')

with open(script_path, "w") as f:
    f.write("#!/usr/bin/env bash\n")
    f.write("esq '{}'".format(query))

new_mode = os.stat(script_path).st_mode | 0o111
os.chmod(script_path, new_mode)


with open(expect_stdout_path, "w") as out:
    with  open(expect_stderr_path, "w") as err:
        path = parent + ":" + os.getenv("PATH")
        print("new path is " + path)
        subprocess.run( [script_path],   stdout=out, stderr=err, env={"PATH": path })
