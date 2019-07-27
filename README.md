# balagetech-dashcommand-parser-obd-elasticsearch
Elasticsearch feeder script for CSV files produced by Dashcommand.

## Usage
```
$ perl dashcommand-csv-parser.pl -d <Data log.csv> -e <elasticsearch ingest node>:9200 2>/dev/null
```

## Notes
 - It is written in Perl and uses the Search::Elasticsearch library.
 - The @timestamp is calculated from the name of the file and the values of 'timestamp' records from the CSV file. Apparently this is how frame timestamps are stored.
 - The stderr is muted because of trace messages overwhelming the console output.
 - The timezone of dates are currently hardwired to 'Europe/Budapest'. Should you need a different timezone then change it in advance.

## Elasticsearch

The Elasticsearch index template mapping and other saved objects like visualizations and dashboards expect version 7.0 or above.
