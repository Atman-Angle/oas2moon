import sys

c = open(\ tests/test_phase1_5.py\).read()
c = c.replace(\assert \\\\\error_responses\\\\\ in op\, \assert \\\\\error_responses\\\\\ in op\\\\n assert \\\\\response_strategy\\\\\ in op\)
open(\tests/test_phase1_5.py\,\w\).write(c)
print(\Done\)