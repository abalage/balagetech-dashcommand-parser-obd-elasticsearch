# balagetech-dashcommand-parser-obd-elasticsearch
Elasticsearch feeder script for CSV files produced by Dashcommand.

It uses the Search::Elasticsearch library.

The @timestamp is calculated from the name of the file and the values of 'timestamp' records from the CSV file.

Usage:
```
$ perl dashcommand-csv-parser.pl -d <Data log.csv> -e <elasticsearch ingest node>:9200 2>/dev/null
```

The stderr is muted because of trace messages overwhelming the console output.

The Elasticsearch index template and other saved objects expect version 7.0 or above.
