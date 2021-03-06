## FUNCTIONS TO EXTRACT DATA OBJECTS FROM SYNAPSE AND CURATE CLINICAL INFO
#####
## ANALYST: BRIAN M. BOT
#####
options(stringsAsFactors=FALSE)
require(synapseClient)
require(rGithubClient)
require(ggplot2)

## GET THE LOCATION OF THIS FILE ON GITHUB
crcscRepo <- getRepo("/Sage-Bionetworks/crcsc")
rUrl <- getPermlink(crcscRepo, "groups/G/dataQc/tcgaCrcClinical-merged.R")

## READ IN FILES AS FORMATED BY TCGA PAN CANCER GROUP - UTILIZING OLD 'DATA' OBJECTS INSTEAD OF FILES
loadTCGAFile <- function(f){
  df <- read.delim(getFileLocation(f), header=TRUE, as.is=TRUE, row.names=1, comment="", quote="", check.names=FALSE, na.strings=c("", "NA", " ", "[Not Available]", "[Not Applicable]", "[Unknown]", "<NA>"))
  return(df)
}
extractTcgaPatientIds <- function(tcgaIds){
  fixIds <- gsub("\\.","-", as.matrix(tcgaIds))
  patientIds <- sapply(strsplit(fixIds, "-", fixed=T), function(x){
    paste(x[1:3], collapse="-")
  })
  return(patientIds)
}


## SYNAPSE FOLDER FOR THE TCGA DATA
synFolder <- "syn2023932"

## GRAB THE CLINICAL DATA
coadClinSyn <- synGet("syn2337874")
coadClin <- loadTCGAFile(coadClinSyn)
coadClin$rns <- rownames(coadClin)

readClinSyn <- synGet("syn2337875")
readClin <- loadTCGAFile(readClinSyn)
readClin$rns <- rownames(readClin)

## REPLACE FU INFO IN CLINICAL TABLE WITH THAT IN FOLLOW UP TABLE
crcClin <- merge(x=coadClin, y=readClin, all=T)
rownames(crcClin) <- crcClin$rns
crcClin$rns <- NULL
clin <- crcClin
clin$vital_status[ clin$vital_status %in% c("Dead", "DECEASED") ] <- "DECEASED"
clin$vital_status[ clin$vital_status %in% c("Alive", "LIVING") ] <- "LIVING"

## GRAB THE UPDATED FOLLOW UP DATA
coadFUSyn <- synGet("syn2320334")
coadFU <- read.delim(getFileLocation(coadFUSyn), header=T, as.is=T, row.names=1, comment="", quote="", na.strings=c("", "NA", " "))
coadFU$rns <- rownames(coadFU)
readFUSyn <- synGet("syn2320324")
readFU <- read.delim(getFileLocation(readFUSyn), header=T, as.is=T, row.names=1, comment="", quote="", na.strings=c("", "NA", " "))
readFU$rns <- rownames(readFU)

crcFU <- merge(x=coadFU, y=readFU, all=T)
rownames(crcFU) <- crcFU$rns
crcFU$rns <- NULL

for( i in unique(extractTcgaPatientIds(rownames(crcFU))) ){
  tmp <- crcFU[ grep(i, rownames(crcFU), fixed=T), ]
  idd <- tmp$vital_status %in% c("DECEASED", "Dead")
  if( any(idd) ){
    clin[i, "vital_status"] <- "DECEASED"
    clin[i, "days_to_death"] <- min(c(tmp$days_to_death[idd], clin$days_to_death[i]), na.rm=T)
    clin[i, "days_to_last_followup"] <- NA
  }
  tmp2 <- tmp[-idd, ]
  if( any(!is.na(tmp2$days_to_last_followup)) ){
    if( !is.na(clin$vital_status[i]) ){
      if( clin$vital_status[i] == "LIVING" ){
        clin[i, "days_to_last_followup"] <- max(c(tmp2$days_to_last_followup, clin$days_to_last_followup[i]), na.rm=T)
      }
    }
  }
}


## GRAB THE AUXILARY DATA
coadAuxSyn <- synGet("syn2336029")
coadAux <- read.delim(getFileLocation(coadAuxSyn), header=T, as.is=T, row.names=1, comment="", quote="", na.strings=c("", "NA", " ", "[Not Available]", "[Not Applicable]", "[Unknown]", "<NA>"))
coadAux$rns <- rownames(coadAux)
readAuxSyn <- synGet("syn2336062")
readAux <- read.delim(getFileLocation(readAuxSyn), header=T, as.is=T, row.names=1, comment="", quote="", na.strings=c("", "NA", " ", "[Not Available]", "[Not Applicable]", "[Unknown]", "<NA>"))
readAux$rns <- rownames(readAux)

crcAux <- merge(x=coadAux, y=readAux, all=T)
rownames(crcAux) <- crcAux$rns
crcAux$rns <- NULL

clin$msi <- NA
clin$msi <- crcAux[rownames(clin), "mononucleotide_and_dinucleotide_marker_panel_analysis_status"]

clinOut <- data.frame(id=rownames(clin),
                      age=as.numeric(clin$age_at_initial_pathologic_diagnosis),
                      gender=tolower(clin$gender),
                      stage=clin$pathologic_stage,
                      tStage=clin$pathologic_T,
                      nStage=clin$pathologic_N,
                      mStage=clin$pathologic_M,
                      tumorLocation=clin$anatomic_neoplasm_subdivision,
                      dfsMo=NA,
                      dfsStat=NA,
                      osMo=as.numeric(clin$days_to_last_followup)*12/365,
                      osStat=ifelse(clin$vital_status=="DECEASED", 1, 0),
                      batch=NA,
                      microsatelite=clin$msi,
                      cimp=NA,
                      adjChemo=NA)
clinOut$osMo[which(clin$vital_status=="DECEASED")] <- as.numeric(clin$days_to_death[which(clin$vital_status=="DECEASED")])*12/365


## WRITE OUT AN ACTIVITY THAT CAPTURES WHAT WAS USED IN OUR ANALYSIS
act <- Activity(name="Clinical curation script", used=list(readClinSyn, coadClinSyn, coadFUSyn, readFUSyn, coadAuxSyn, readAuxSyn, list(url=rUrl, name=basename(rUrl), wasExecuted=TRUE)))
act <- synStore(act)

## CLINICAL FILE
tcgaCrcClinFile <- file.path(tempdir(), "TCGACRC_clinical-merged.tsv")
write.table(clinOut, file=tcgaCrcClinFile, sep="\t", quote=FALSE, row.names=FALSE)

clinFile <- File(path=tcgaCrcClinFile, parentId=synFolder)
generatedBy(clinFile) <- act
clinFile <- synStore(clinFile)

