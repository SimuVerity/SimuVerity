[![Documentation Status](https://readthedocs.org/projects/python-anesthesia-simulator/badge/?version=latest)](https://python-anesthesia-simulator.readthedocs.io/en/latest/?badge=latest)
<img src ="https://img.shields.io/github/last-commit/AnesthesiaSimulation/Python_Anesthesia_Simulator" alt="GitHub last commit"> 

# Python_Anesthesia_Simulator

The Python Anesthesia Simulator (PAS) models the effect of drugs on physiological variables during total intravenous anesthesia. It is particularly dedicated to the control community, to be used as a benchmark for the design of multidrug controllers. The available drugs are propofol, remifentanil, norepinephrine, and atracurium the outputs are the Bispectral Index (BIS), tolerance to laryngoscopy (TOL), loss of consciousness (LOC), mean arterial pressure (MAP), cardiac output (CO), total peripheral resistence (TPR), stroke volume (SV), heart rate (HR) and Train of four level (TOF). PAS includes different well-known models along with their uncertainties to simulate inter-patient variability. Blood loss can also be simulated to assess the controller's performance in a shock scenario. Finally, PAS includes disturbance profiles calibrated on clinical data to facilitate the evaluation of the controller's performances in realistic condition.

- **Documentation and examples:** <https://python-anesthesia-simulator-doc.readthedocs.io>
- **Associated publication:** <https://doi.org/10.21105/joss.05480>

## Installation

Use pip to install the package:

```python
    pip install python-anesthesia-simulator
```

Or, to get the latest version, clone this repository and install the package with:

```python
    pip install .
```
## Citation

To cite PAS in your work, cite this work:

```
Aubouin-Pairault et al., (2023). PAS: a Python Anesthesia Simulator for drug control. Journal of Open Source Software, 8(88), 5480, https://doi.org/10.21105/joss.05480
```

## Guidelines

Contribution and discussions are welcomed! Please feel free to use the [issue tracker](https://github.com/AnesthesiaSimulation/Python_Anesthesia_Simulator/issues) ensuring that you follow our [contribution guide](https://python-anesthesia-simulator-doc.readthedocs.io/latest/contributing.html) and our [Code of Conduct](./CODE_OF_CONDUCT.md).

## Structure

    .
    ├─── src
    |   ├─── python_anesthesia_simulator           # Simulator library + metrics function
    |
    ├── tests              # files for testing the package
    |
    ├── docs               # files for generating the docs
    | 
    ├── LICENSE
    ├── pyproject.toml      # packaging file
    ├── requirements.txt
    ├── README.md
    └── .gitignore          

## License

_GNU General Public License 3.0_

## Authors

Bob Aubouin--Pairault, Michele Schiavo, Erhan Yumuk
