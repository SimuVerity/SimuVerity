.. Python Anesthesia Simulator documentation master file, created by
   sphinx-quickstart on Sat Apr  1 13:30:32 2023.
   You can adapt this file completely to your liking, but it should at least
   contain the root `toctree` directive.

Welcome to Python Anesthesia Simulator's documentation!
=======================================================

The Python Anesthesia Simulator (PAS) models the effect of drugs on physiological variables during total intravenous anesthesia. It is particularly dedicated to the control community, to be used as a benchmark for the design of multidrug controllers. The available drugs are **propofol**, **remifentanil**, **norepinephrine**, and **atracurium** the outputs are the Bispectral Index (**BIS**), tolerance to laryngoscopy (**TOL**), loss of consciousness (**LOC**), mean arterial pressure (**MAP**), cardiac output (**CO**), total peripheral resistence (**TPR**), stroke volume (**SV**), heart rate (**HR**) and train of four (**TOF**). PAS includes different well-known models along with their uncertainties to simulate inter-patient variability. Blood loss can also be simulated to assess the controller's performance in a shock scenario. Finally, PAS includes disturbance profiles calibrated on clinical data to facilitate the evaluation of the controller's performances in realistic condition.

If you are using PAS for your research, please cite the previous publications:
https://doi.org/10.21105/joss.05480


.. toctree::
   :maxdepth: 2
   :caption: Contents:

   intro
   modelling_anesthesia
   python_anesthesia_simulator
   examples
   matlab
   contributing

