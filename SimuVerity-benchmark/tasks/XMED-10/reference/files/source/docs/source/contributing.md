# Contributing to Python Anesthesia Simulator

## Introduction

First off, thank you for considering contributing to Python Anesthesia Simulator. It's people like you that will make this simulator a great democratized tool. ❤️

All members of our community are expected to follow our [code-of-conduct](https://github.com/AnesthesiaSimulation/Python_Anesthesia_Simulator/blob/main/CODE_OF_CONDUCT.md). Please make sure you are welcoming and friendly in all of our spaces.

Following these guidelines helps to communicate that you respect the time of the developers managing and developing this open source project. In return, they should reciprocate that respect in addressing your issue, assessing changes, and helping you finalize your pull requests.

Python Anesthesia Simulator is an open source project, and we love to receive contributions from people! There are many ways to contribute:

- Reporting bugs
- Suggesting enhancements
- Writing or editing documentation or examples
- Submitting code changes
- Spreading the word about Python Anesthesia Simulator.

## Ground Rules

### Reporting a bug or suggesting an enhancement through the issue tracker

To report a bug or suggest an enhancement, please open an issue in the [issue tracker](https://github.com/AnesthesiaSimulation/Python_Anesthesia_Simulator/issues).

For **bug reports**, please include the following information:

- A description of the problem
- A minimal coding example to reproduce the problem
- Provide project and platform versions (e.g., Python version, OS, dependencies).

Before submitting an **enhancement**:

- Ensure you are using the latest version, particularly have a look at the dev branch of the repository.
- Review the documentation to check if the feature already exists.
- Search the [issue tracker](https://github.com/AnesthesiaSimulation/Python_Anesthesia_Simulator/issues) for similar suggestions.
- Ensure the feature aligns with the project’s goals.

We will address your issue as soon as possible.

### Submitting code changes or documentation updates

> #### Legal Notice
> When contributing to this project, you must agree that you have authored 100% of the content, that you have the necessary rights to the content, and that the content you contribute may be provided under the project license.

Code changes or documentation are made through pull requests as both are part of the same repository.

Contributions to the project are made through GitHub pull requests. The steps to submit a pull request are as follows. For a complete guide on how to contribute, please refer to the [GitHub documentation](https://docs.github.com/en/get-started/quickstart/contributing-to-projects).

1. Fork the repository and clone it locally:
   ```bash
   git clone https://github.com/your-username/Python_Anesthesia_Simulator.git
   ```
2. Install dependencies:
   ```bash
   pip install -e .[test]
   ```
3. Run tests to ensure the setup works:
   ```bash
   pytest --cov=python_anesthesia_simulator tests/
   ```
4. Create a feature branch:
   ```bash
   git checkout -b feature/your-feature-name
   ```
5. Develop, test, and commit your changes:
   ```bash
   git add .
   git commit -m "feat: add feature description"
   ```
6. Push your branch and create a pull request.
7. In your pull request, please include:
   - A description of the changes made
   - Any relevant issue numbers
   - A checklist of tasks completed (e.g., tests added, documentation updated)

Your pull request will be reviewed by the maintainers. They may request changes or provide feedback. Please be responsive to their comments and suggestions.

The following steps can be taken to check locally changes made to the **documentation**:

1. Install documentation dependencies
   ```bash
   pip install -r docs/requirements
   ```
2. Generate the html pages of the documentation
   ```bash
   cd docs
   make html
   ```
   Eventually the documentation can be regenerated from scratch by cleaning the build folder with ```make clean``` 
3. Look at the results by opening the html files located in ```docs/build/html/```.

## Conventions

Conventions are important to ensure a consistent and high-quality codebase. Please follow these conventions when contributing to the project.

### Style for code

- Follow the [PEP 8](https://www.python.org/dev/peps/pep-0008/) style guide for Python code.

### Commit message conventions

- Use the [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) specification for commit messages.
