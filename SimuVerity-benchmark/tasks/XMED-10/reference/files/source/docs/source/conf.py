# Configuration file for the Sphinx documentation builder.
#
# This file only contains a selection of the most common options. For a full
# list see the documentation:
# https://www.sphinx-doc.org/en/master/usage/configuration.html

# -- Path setup --------------------------------------------------------------

# If extensions (or modules to document with autodoc) are in another directory,
# add these directories to sys.path here. If the directory is relative to the
# documentation root, use os.path.abspath to make it absolute, like shown here.
#
import os
import sys
# sys.path.insert(0, os.path.abspath('..'))
sys.path.insert(0, os.path.abspath('../..'))


# -- Project information -----------------------------------------------------

project = 'Python Anesthesia Simulator'
copyright = '2023, Bob Aubouin-Pairault'
author = 'Bob Aubouin-Pairault'

# The full version, including alpha/beta/rc tags
# release = '1.0.0'


# -- General configuration ---------------------------------------------------

# Add any Sphinx extension module names here, as strings. They can be
# extensions coming with Sphinx (named 'sphinx.ext.*') or your custom
# ones.
extensions = [
    'numpydoc',
    'sphinx.ext.autodoc',
    'sphinx.ext.autosummary',
    'nbsphinx',
    'myst_parser',
    "sphinx.ext.graphviz",
]

# list of autodoc directive flags that should be automatically applied
# to all autodoc directives.
autodoc_default_options = {
    'members': True,
    'inherited-members': True,
    'exclude-members': '__init__, __weakref__, __repr__, __str__'
}

# adding latex packages
latex_elements = {
    'preamble': r'''
        \usepackage{xcolor}
    ''',
}

nbsphinx_allow_errors = True  # Continue through Jupyter errors

# Add any paths that contain templates here, relative to this directory.
templates_path = ['_templates']

# List of patterns, relative to source directory, that match files and
# directories to ignore when looking for source files.
# This pattern also affects html_static_path and html_extra_path.
exclude_patterns = []


# -- Options for HTML output -------------------------------------------------

# The theme to use for HTML and HTML Help pages.  See the documentation for
# a list of builtin themes.
#
html_theme = "furo"
html_logo = 'images/logo_pas.png'
html_static_path = ['_static']

# Add any paths that contain custom static files (such as style sheets) here,
# relative to this directory. They are copied after the builtin static files,
# so a file named "default.css" will overwrite the builtin "default.css".
# html_static_path = ['_static']

# numpydoc configuration
numpydoc_show_class_members = False

# If true, the current module name will be prepended to all description
# unit titles (such as .. function::).
add_module_names = False

autosummary_generate = True
