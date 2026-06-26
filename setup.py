"""Setup configuration for the Change Request Risk Assessor."""

from setuptools import setup, find_packages

setup(
    name="risk-assessor",
    version="1.0.0",
    description="Automated risk scoring for change requests",
    author="DevOps Team",
    python_requires=">=3.11",
    package_dir={"": "src"},
    packages=find_packages(where="src"),
    install_requires=[
        "flask==3.0.0",
        "gunicorn==21.2.0",
    ],
    extras_require={
        "dev": [
            "pytest==7.4.3",
            "pytest-cov==4.1.0",
            "flake8==6.1.0",
            "bandit==1.7.6",
        ],
    },
)
