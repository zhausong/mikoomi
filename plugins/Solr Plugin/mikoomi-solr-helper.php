<?php
#
if ($argc != 3) {
   exit ;
}

if (!file_exists($argv[1])) {
   exit ;
}

$xml = simplexml_load_file($argv[1]) ;

$zabbix_name = $argv[2] ;

#print ("Printing CORE entry names\n") ;
#----------------------------------------------------------------------------------------------------
# Currently we only want numDocs and MaxDoc from CORE !
#----------------------------------------------------------------------------------------------------
foreach ($xml->xpath('/solr/solr-info/CORE/entry') as $entry) {
         $entry_name = str_replace(' ', '_', trim($entry->name)) ;
         $entry_class = str_replace(' ', '_', trim($entry->class)) ;
         $entry_version = str_replace(' ', '_', trim($entry->version)) ;
         $entry_description = trim($entry->description) ;
         foreach ($entry->stats->stat as $stat) {
                  $stat_name = str_replace(' ', '_', $stat['name']) ;
                  $stat_value = trim($stat) ;
                  if ($entry_name == "searcher" and ($stat_name == "numDocs" or $stat_name == "maxDoc")) {
                     print("$zabbix_name ${stat_name} $stat_value\n") ;
                  }
                  #print("next....") ;
                  #print_r($stat->asXML()) ;
        }
               
}

#print ("Printing CACHE entry names\n") ;
#----------------------------------------------------------------------------------------------------
# Currently nothing required from CACHE
#----------------------------------------------------------------------------------------------------
foreach ($xml->xpath('/solr/solr-info/CACHE/entry') as $entry) {
         $entry_name = str_replace(' ', '_', trim($entry->name)) ;
         $entry_class = str_replace(' ', '_', trim($entry->class)) ;
         $entry_version = str_replace(' ', '_', trim($entry->version)) ;
         $entry_description = trim($entry->description) ;
         foreach ($entry->stats->stat as $stat) {
                  #$stat_name = $stat['name'] ;
                  $stat_name = str_replace(' ', '_', $stat['name']) ;
                  $stat_value = trim($stat) ;
                  #print("cache_${entry_name}_${stat_name} $stat_value\n") ;
                  #print("next....") ;
                  #print_r($stat->asXML()) ;
        }
               
}

$search_entry_name_string_array = array(" ", 
                             "/",
                            "org.apache.solr.handler.component.",
                            "org.apache.solr.handler."
                            ) ;
$replace_entry_name_string_array = "_" ;

$search_entry_value_string_array = array( 
                             " KB",
                             " MB",
                             " GB",
                             " Bytes"
                            ) ;
$replace_entry_value_string_array = "" ;


#print ("Printing QUERYHANDLER entry names\n") ;
foreach ($xml->xpath('/solr/solr-info/QUERYHANDLER/entry') as $entry) {
         $entry_name = preg_replace("/^_/", "", str_replace($search_entry_name_string_array, $replace_entry_name_string_array, trim($entry->name))) ;
         #----------------------------------------------------------------------------------------------------
         # Skip "ReplicationHandler" since it is covered under the entry_name "replication"
         #----------------------------------------------------------------------------------------------------
         if ($entry_name == "ReplicationHandler") {
            continue ;
         }
         foreach ($entry->stats->stat as $stat) {
                  $stat_name = $stat['name'] ;
                  $stat_value = trim(str_replace($search_entry_value_string_array, $replace_entry_value_string_array, $stat)) ;
                  #----------------------------------------------------------------------------------------------------
                  # Skip handlerStart since it is some epoch time (not much use currently) and any stat that has not been initialized.
                  #----------------------------------------------------------------------------------------------------
                  if ($stat_name != "handlerStart" and ($stat_value != "not initialized yet" and $stat_value != "NaN")) {
                     #----------------------------------------------------------------------------------------------------
                     # indexSize requires special handling. We need emit the numeric value for the index and the metric for the index size seperately.
                     #----------------------------------------------------------------------------------------------------
                     if ($stat_name == "indexSize") {
                         $stat_value_new = str_replace($search_entry_value_string_array, $replace_entry_value_string_array, trim($stat)) ;
                         $stat_value_split = split(" ", trim($stat)) ;
                         print("$zabbix_name ${entry_name}_${stat_name} $stat_value_new\n") ;
                         print("$zabbix_name ${entry_name}_${stat_name}_unit $stat_value_split[1]\n") ;
                     } else {
                        print("$zabbix_name ${entry_name}_${stat_name} $stat_value\n") ;
                     }
                  }
                  #print("next....") ;
                  #print_r($stat->asXML()) ;
        }

}

?>
