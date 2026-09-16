import sys

c = open('tests/test_phase1_5.py').read()
c = c.replace(
    'assert isinstanceof(op["error_responses"], list)\n    return True',
    'assert isinstanceof(op["error_responses"], list)\n        assert op["response_strategy"]["kind"] in ["single_result", "unit_result", "response_enum", "no_content", "unsupported_media_type"]\n    return True'
)
open('tests/test_phase1_5.py', 'w').write(c)
print('Done')
