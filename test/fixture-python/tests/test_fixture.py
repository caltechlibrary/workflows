import os
import time

import fixture_pkg


def test_package_is_installed():
    assert fixture_pkg.greet("there") == "Hello, there"
    assert fixture_pkg.__version__ == "0.1.0"


def test_env_input_reaches_the_tests():
    # python-tests.yml's `env` input sets these; CI passes them.
    assert os.environ.get("TZ") == "America/Los_Angeles"
    assert time.tzname[0] == "PST"
    assert os.environ.get("FIXTURE_VALUE") == "a=b c"
