from setuptools import find_packages
from setuptools import setup

setup(name='sample',
      version='0.1',
      description='A sample python project',
      url='http://github.com/majid/',
      author='Majid Laali',
      author_email='majid@elementai.com',
      license='MIT',
      packages=find_packages('src'),
      package_dir={'': 'src'},
      zip_safe=False)
