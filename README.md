This projects contains a Ruby script that uses RCUK GtR API and API 2 to extract
project data registered in RCUK's Gateway to Research
and find all Doctoral Training Centres/Partnership grants.

Extracted CDT/DTPs are saved to a CSV file in the root directory of the project.

See http://gtr.rcuk.ac.uk/resources/GtR-1-API-v3.0.pdf for RCUK GtR API details.

See http://gtr.rcuk.ac.uk/resources/GtR-2-API-v1.6.pdf for RCUK GtR API 2 details.

To run the Ruby script to extract the CDT/DTP project data, from project root do:
```
ruby rcuk_gtr_api_cdt_dtp_extractor.rb
```