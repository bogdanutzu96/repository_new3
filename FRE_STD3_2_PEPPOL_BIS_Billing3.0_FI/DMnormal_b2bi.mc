/*==============================================================================
** Program/Module :     DMnormal_b2bi.mc
** Description :        Datamapper maincode for SEB maps, migrated to B2Bi from XIB
** Type : 				Maincode
** Component Type : 	Datamapper
** Supported Products : B2Bi >=  2.6
**==============================================================================
** HISTORY
** 20XXXXXX SEB				1.0.0	initial version.
** 20180605	phedlin		1.0.1	migrated to B2Bi
** 20181203	phedlin		1.0.2	removed code to reuse same loggerid as input, added syncpoint
** 20190411	phedlin		1.0.3	added the AddMapOutputNameAttribute statement allowing this 
								maincode to be used with object maps with multiple outputs.
** 20190924 phedlin		1.0.4	Function CreateFilename() renamed to GetDynamicString() and moved
								to its own library "PARAMETER". Maincode updated accordingly.
** 20200330 phedlin		1.0.5	added call to 'SEBUTIL.SetMessagePriority' in DMevent_BeforeCloseInput.
								Removed (unused?) variable '#Variable for SAS/ITA DECLARE $Rechner_i INTEGER'
** 20200824 phedlin		1.0.6	removed (unused?) variable '$w_supplier', added $In_Filename variable	
** 20200824 phedlin		1.0.7	added back removed 'reuse-same-loggerid' code from v1.0.2
** 20201019	jrosenqv	1.0.8	added genericrecord inheritance fixed bug in ErrorBeforeCloseInput
** 20201028 phedlin		1.0.9	again removed 'reuse-same-loggerid' code as it causes circular logger references
** 20210817 mmcpheat	1.0.10 Introduced a timer-timeout function when setting Correlations in table server.
**==============================================================================*/
INCLUDE "frameworkDM.s4"			ONCE;
INCLUDE "transgateway.s4h"			ONCE;
INCLUDE "ta_ftp.s4h"				ONCE;
INCLUDE "ta_email.s4h"				ONCE;
INCLUDE "mimeout_attribute.s4h"		ONCE;	
INCLUDE "sl_tag.s4h"				ONCE;
INCLUDE "datefld.s4h" 				ONCE;
INCLUDE "sl_date.s4h" 				ONCE;
INCLUDE "SEBKort_TACHandling.s4h" 	ONCE;
INCLUDE "SEBKort_Attributes.s4h" 	ONCE;
INCLUDE "SEBParamFun.s4h"		 	ONCE;
INCLUDE "curdec.s4h"				ONCE;
INCLUDE "mbc_attributeNames.s4h"	ONCE; 
INCLUDE "mbc_general.s4h" 			ONCE;

/*()----------------------------------------------------------------------------
** Update these if maincode is updated 
**----------------------------------------------------------------------------*/
DECLARE $PgmName		= "DMnormal_b2bi.mc"	CONSTANT STRING;
DECLARE $PgmRevision	= "1.0.10"				CONSTANT STRING;


/*()----------------------------------------------------------------------------
** Variable declarations
**----------------------------------------------------------------------------*/
DECLARE $AttributeNames[]			STRING;
DECLARE $AttributeValue				STRING;
DECLARE $SessionId					INTEGER;
DECLARE $MessageId					INTEGER;
DECLARE $NewMessageIds[]			INTEGER;
DECLARE $AttributeFlag				INTEGER;
DECLARE $FtpAttributeString			STRING;
DECLARE $FtpOverride				RECORD TA_FTP.SendMethodOverrideAttribute;
DECLARE $FtpOverrideString			STRING;
DECLARE $FtpInputAttribute			RECORD TA_FTP.ReceiveInfoAttribute;	
DECLARE $FtpInputAttributeString	STRING;
DECLARE $EmailOverride				RECORD TA_EMAIL.SendMethodOverrideAttribute;
DECLARE $EmailOverrideString		STRING;
DECLARE $MimeOutOverride			RECORD MIMEOUT_ATTRIBUTE.OverrideMimeOutConfiguration;
DECLARE $MimeOutOverrideString		STRING;
DECLARE $SEBKort_PartnerAttribute	RECORD SEBKORT_ATTRIBUTES.SEBKort_PartnerAttribute;
DECLARE $SEBKort_StartpostAttribute	RECORD SEBKORT_ATTRIBUTES.SEBKort_StartpostAttribute;

#Variable for Error reporting
DECLARE $ErrorRecords[]				RECORD SEBKORT_ATTRIBUTES.ErrorRecord;
DECLARE $ErrorRecordString			STRING;
DECLARE $MapObjName					STRING;
DECLARE $MapObjType					STRING;
DECLARE $ErrorText					STRING;
DECLARE $ErrorCode					INTEGER;
DECLARE $DTreePath					STRING;

DECLARE $True = 1					CONSTANT INTEGER;
DECLARE $False = 0 					CONSTANT INTEGER;

DECLARE $DM_debug					INTEGER;
DECLARE $DM_event_debug				INTEGER;
DECLARE $FTP_Exist					INTEGER;

#Variables for Attributes assignment
DECLARE $In_Filename				STRING;
DECLARE $Out_Filename				STRING;
DECLARE $Out_Password				STRING;
DECLARE $Out_EmailSubject			STRING;
DECLARE $StopMessageReason			STRING;
DECLARE $logWarning					STRING;
DECLARE $Simulator					INTEGER;
DECLARE $LogRef_Attribute			RECORD SEBKORT_ATTRIBUTES.SEBKort_LogRefAttribute;
DECLARE $LogRef_CompanyName			STRING;
DECLARE $LogRef_OrgNr				STRING;
DECLARE $LogRef_GLN					STRING;
DECLARE $LogRef_InvoiceNr			STRING;
DECLARE $LogRef_Status				STRING;
DECLARE $LogRef_Tag1				STRING;
DECLARE $LogRef_Value1				STRING;
DECLARE $LogRef_Tag2				STRING;
DECLARE $LogRef_Value2				STRING;
DECLARE $LogRef_Tag3				STRING;
DECLARE $LogRef_Value3				STRING;
DECLARE $MapName					STRING;
DECLARE $TimerData[]			STRING;

DECLARE $GenericRecord				RECORD SEBKORT_ATTRIBUTES.GenericRecord;
DECLARE $EmptyGenericRecord			CONSTANT RECORD SEBKORT_ATTRIBUTES.GenericRecord;

#Variables for Properties
DECLARE $Key						STRING;
DECLARE $DynProp[]					STRING;
DECLARE $EmptyProp[]				CONSTANT STRING;

#Variables for ParamFun
DECLARE $Param6Str					STRING;
DECLARE $Param6Arr[][]				STRING;


/*()----------------------------------------------------------------------------
** DATACODE, INTERFACECODE, MAPCODE
** The generator tags (%DATACODE etc.) has to be located first on the line.
**----------------------------------------------------------------------------*/
	%DATACODE
	%INTERFACECODE
	%MAPCODE


DECLARE MODULE MAIN {

	/*()----------------------------------------------------------------------------
	** MODULE_INIT
	**----------------------------------------------------------------------------*/
	DECLARE STATEMENT MODULE_INIT {
		RETURN;
	 }


	/*()----------------------------------------------------------------------------
	** Construct
	**----------------------------------------------------------------------------*/
	DECLARE PUBLIC STATEMENT Construct { 
		%CONSTRUCTORCODE
		RETURN;
	}

	/*()----------------------------------------------------------------------------
	** Destroy
	**----------------------------------------------------------------------------*/
	DECLARE PUBLIC STATEMENT Destroy {
		%DESTRUCTORCODE
		RETURN;
	}

	/*()----------------------------------------------------------------------------
	** ExecuteMap
	**----------------------------------------------------------------------------*/
	DECLARE PUBLIC STATEMENT ExecuteMap {
		
		TRY {
			
			%ACTIVATECODE
			
			#Map succeeded
			IF $DM_Debug { LOG FORMAT("Map %s executed successfully (Maincode: %s  Revision: %s)",$MapName,$PgmName,$PgmRevision) TYPE "DEBUG"; }
			
		} CATCH $Exception
			WHEN OTHERS {
				
				#All errors during the conversion are trapped here
				IF $DM_Debug { LOG FORMAT("Map %s (Maincode: %s  Revision: %s) failed with Exception %s",$MapName,$PgmName,$PgmRevision,$Exception) TYPE "ERROR"; }

				%ERRORCODE
			} 

		%RESETCODE
		
		RETURN;
	}
    
	/*()----------------------------------------------------------------------------
	** Event
	**----------------------------------------------------------------------------*/
	DECLARE PUBLIC STATEMENT Event IN $Event DATA IN $Data PRIMITIVE {

	#Map event
	CASE $Event 

		/* Event: BeforeOpenInput */
		WHEN $DMevent_BeforeOpenInput {

			#Initialize variables
			$logWarning			= "";
			$In_Filename		= "";
			$Out_Filename		= "";
			$Out_Password		= "";
			$Out_EmailSubject	= "";
			$StopMessageReason	= "";
			$LogRef_CompanyName = "";
			$LogRef_OrgNr       = "";
			$LogRef_GLN         = "";
			$LogRef_InvoiceNr   = "";
			$LogRef_Status      = "";
			$LogRef_Tag1        = "";
			$LogRef_Value1      = "";
			$LogRef_Tag2        = "";
			$LogRef_Value2      = "";
			$LogRef_Tag3        = "";
			$LogRef_Value3      = "";
			$GenericRecord		= $EmptyGenericRecord;

			#Get the name of the map
			$MapName = DMU.GetCurrentMapObjName();

			#Get MessageId for the input message
			DMU.GetInputMessageId $SessionId MESSAGEID $MessageId;
			
			#Create a syncpoint
			MBC_HIERCHMSGENV.CreateSyncpoint $SessionId;

			#Read the DebugFlag attribute
			TRY {
				NOLOG { $AttributeValue = MBC_HIERCHMSGENV.GetAttribute($SessionId,$MessageId,"DebugFlag"); }
				IF SL_STRING.ToUpper($AttributeValue) = "Y" OR SL_STRING.ToUpper($AttributeValue) = "TRUE" {
					$DM_Debug = $True;
				}
			} CATCH $Exception
				WHEN OTHERS {
					#Nothing
				}
				
			#In simulator mode, debug is always enabled.
			IF $Simulator {
				$DM_Debug = $True;
				$DM_event_debug = $True; 
				LOG "Map is executing in simulation mode, enabling all debug..." TYPE "DEBUG";
			}
			
			#Start!
			IF $DM_Debug { LOG FORMAT("Executing map %s (Maincode: %s  Revision: %s)",$MapName,$PgmName,$PgmRevision) TYPE "DEBUG"; }

			#Read the SEBKort_PartnerAttribute
			TRY {
				NOLOG { $AttributeValue = MBC_HIERCHMSGENV.GetAttribute($SessionId,$MessageId,"SEBKort_PartnerAttribute"); }
				UNSERIALIZE $AttributeValue INTO $SEBKort_PartnerAttribute;
			} CATCH $Exception WHEN OTHERS {
				#Nothing
			}   

			#Read the SEBKort_StartpostAttribute
			TRY {
				NOLOG { $AttributeValue = MBC_HIERCHMSGENV.GetAttribute($SessionId,$MessageId,"SEBKort_StartpostAttribute"); }
				UNSERIALIZE $AttributeValue INTO $SEBKort_StartpostAttribute; 
			} CATCH $Exception 
				WHEN OTHERS {
					#Nothing
				}

			#Get the input filename
			TRY {
				NOLOG { $In_Filename = MBC_HIERCHMSGENV.GetAttribute($SessionId,$MessageId,"B2BXGIReceive_ConsumptionFilename"); }
			} CATCH $Exception
				WHEN OTHERS {
					$In_Filename = "";
				}
		}

		/* Event: AfterOpenInput */
		WHEN $DMevent_AfterOpenInput {
			IF $DM_event_debug { LOG "DMevent_AfterOpenInput" TYPE "DEBUG"; }
		}

		/* Event: BeforeCloseInput */
		WHEN $DMevent_BeforeCloseInput {			
			IF $DM_event_debug { LOG "DMevent_BeforeCloseInput" TYPE "DEBUG"; }
		}
		
		/* Event: AfterCloseInput */
		WHEN $DMevent_AfterCloseInput {
			IF $DM_event_debug { LOG "DMevent_AfterCloseInput" TYPE "DEBUG"; }
		}
		
		/* Event: ErrorBeforeCloseInput */
		WHEN $DMevent_ErrorBeforeCloseInput {
			IF $DM_event_debug { LOG "DMevent_ErrorBeforeCloseInput" TYPE "DEBUG"; }
		}
		
		/* Event: BeforeOpenOutput */
		WHEN $DMevent_BeforeOpenOutput {
			IF $DM_event_debug { LOG "DMevent_BeforeOpenOutput" TYPE "DEBUG"; }
		}

		/* Event: AfterOpenOutput */
		WHEN $DMevent_AfterOpenOutput {
			IF $DM_event_debug { LOG "DMevent_AfterOpenOutput" TYPE "DEBUG"; }
		}

		/* Event: BeforeCloseOutput */
		WHEN $DMevent_BeforeCloseOutput {
			IF $DM_event_debug { LOG "DMevent_BeforeCloseOutput" TYPE "DEBUG"; }
			
			#Propagate the message priority that was set in MetadataProfile / DocumentAgreement attributes
			DMU.GetOutputMessageIds "" SessionId $SessionId MessageIds $NewMessageIds;
			FOR $xI = 1 TO ARRAYSIZE($NewMessageIds) {
				SEBUTIL.SetMessagePriority $SessionId MessageId $MessageId NewMessageId $NewMessageIds[$xI];
			}
			
			#Set output name in case of an object map with multiple outputs
			AddMapOutputNameAttribute;
		}
		
		/* Event: AfterCloseOutput */
		WHEN $DMevent_AfterCloseOutput {
			IF $DM_event_debug { LOG "DMevent_AfterCloseOutput" TYPE "DEBUG"; }
		}

		/* Event: ErrorBeforeCloseOutput */
		WHEN $DMevent_ErrorBeforeCloseOutput {
			IF $DM_event_debug { LOG "DMevent_ErrorBeforeCloseOutput" TYPE "DEBUG"; }
		}

		/* Event: BeforeReadInput */
		WHEN $DMevent_BeforeReadInput {
			IF $DM_event_debug { LOG "DMevent_BeforeReadInput" TYPE "DEBUG"; }
		}
		
		/* Event: AfterReadInput */
		WHEN $DMevent_AfterReadInput {
			IF $DM_event_debug { LOG "DMevent_AfterReadInput" TYPE "DEBUG"; }
		}

		/* Event: ErrorReadInput */
		WHEN $DMevent_ErrorReadInput {			
			IF $DM_event_debug { LOG "DMevent_ErrorReadInput" TYPE "DEBUG"; }
			
			#Extract all output errors into an Error record
			FOR $xI = 1 TO DMU.GetNrOfErrors() {

				DMU.GetError		$xI
					MAPOBJNAME		$MapObjName
					MAPOBJTYPE		$MapObjType
					ERROR			$ErrorText
					ERRORCODE		$ErrorCode
					DATATREEPATH	$DTreePath;

				$ErrorRecords[$xI].$MapObjName = $MapObjName;
				$ErrorRecords[$xI].$MapObjType = $MapObjType;
				$ErrorRecords[$xI].$ErrorText = $ErrorText;
				$ErrorRecords[$xI].$ErrorCode = $ErrorCode;
				$ErrorRecords[$xI].$DTreePath = $DTreePath;

			}

			#Assign an Error attribute for further reporting back to partner.
			SERIALIZE $ErrorRecords INTO $ErrorRecordString;
			MBC_HIERCHMSGENV.SetAttribute	$SessionId
								MessageId	$MessageId
								Name		SEBKORT_Attributes.$ErrorRecord
								Value		$ErrorRecordString;

			LOG "Number of input errors: " & DMU.GetNrOfErrors() & ", Error: " & $ErrorRecordString TYPE "ERROR";
		}

		/* Event: BeforeWriteOutput */
		WHEN $DMevent_BeforeWriteOutput {		
			IF $DM_event_debug { LOG "DMevent_BeforeWriteOutput" TYPE "DEBUG"; }
			
			#If $StopMessageReason is set, we log and stop the message. No error, just warning.
			IF $StopMessageReason <> "" {
				DMU.GetInputMessageId $SessionId MESSAGEID $MessageId;
				DMU.AddWarning $StopMessageReason;
				MBC_HIERCHMSGENV.StopMessage $SessionId MessageId $MessageId;
			}
			IF $logWarning <> "" {
				DMU.GetInputMessageId $SessionId MESSAGEID $MessageId;
				DMU.AddWarning $logWarning;
			}
		}    

		/* Event: AfterWriteOutput */
		WHEN $DMevent_AfterWriteOutput {			
			IF $DM_event_debug { LOG "DMevent_AfterWriteOutput" TYPE "DEBUG"; }
			
			#Set output filename
			IF $Out_FileName <> "" {
			
				IF $DM_debug = $True {
					LOG "Out_Filename: " & $Out_Filename TYPE "DEBUG";
				}
				$Out_FileName = PARAMETER.GetDynamicString($SessionId,$MessageId,$Out_FileName);
				$Out_FileName = SEBUTIL.RemoveSwedishChars($Out_FileName);				
				MBC_HIERCHMSGENV.SetAttribute $SessionId MessageId $MessageId Name $_Attr_TEsnd_ProductionFilename Value $Out_FileName;		
			
			} 

			#Set output password
			IF $Out_Password <> "" {
				
				IF $DM_debug = $True {
					LOG "Out_Password: " & $Out_Password TYPE "DEBUG";
				}
				$SEBKort_PartnerAttribute.$Parameter3 = $Out_Password;
				SERIALIZE $SEBKort_PartnerAttribute INTO $AttributeValue;
				MBC_HIERCHMSGENV.SetAttribute $SessionId MessageId $MessageId Name "SEBKort_PartnerAttribute" Value $AttributeValue;
			}

			#Set output subject
			IF $Out_EmailSubject <> "" {
				
				IF $DM_debug = $True {
					LOG "Out_EmailSubject: " & $Out_EmailSubject TYPE "DEBUG";
				}
				$Out_EmailSubject = PARAMETER.GetDynamicString($SessionId,$MessageId,$Out_EmailSubject);
				MBC_HIERCHMSGENV.SetAttribute $SessionId MessageId $MessageId Name $_Attr_TEsnd_SubjectHeader Value $Out_EmailSubject;
			} 

			#Check if any of the LogRef variables contains any data, if so, make an attribute
			IF ($LogRef_CompanyName <> "") OR ($LogRef_OrgNr <> "") OR ($LogRef_GLN <> "") OR ($LogRef_InvoiceNr <> "") OR
			   ($LogRef_Status <> "") OR ($LogRef_Tag1 <> "") OR ($LogRef_Tag2 <> "") OR ($LogRef_Tag3 <> "") {

				#Create/Update logref attribute
				TRY {	
					NOLOG {
						$AttributeValue = MBC_HIERCHMSGENV.GetAttribute($SessionId,$MessageId,SEBKORT_ATTRIBUTES.$SEBKort_LogRefAttribute );
						UNSERIALIZE $AttributeValue INTO $LogRef_Attribute;
					}
				} CATCH $Exception 
					WHEN OTHERS {
						#Nothing
					}

				IF $LogRef_CompanyName <> "" { $LogRef_Attribute.$CompanyName = $LogRef_CompanyName; }
				IF $LogRef_OrgNr <> "" { $LogRef_Attribute.$OrgNr = $LogRef_OrgNr; }
				IF $LogRef_GLN <> "" { $LogRef_Attribute.$GLN = $LogRef_GLN; }
				IF $LogRef_InvoiceNr <> "" { $LogRef_Attribute.$InvoiceNr = $LogRef_InvoiceNr; }
				IF $LogRef_Status <> "" { $LogRef_Attribute.$Status = $LogRef_Status; }
				IF $LogRef_Tag1 <> "" {
					$LogRef_Attribute.$Tag1 = $LogRef_Tag1;
					$LogRef_Attribute.$Value1 = $LogRef_Value1;
				}
				IF $LogRef_Tag2 <> "" {
					$LogRef_Attribute.$Tag2 = $LogRef_Tag2;
					$LogRef_Attribute.$Value2 = $LogRef_Value2;
				}
				IF $LogRef_Tag3 <> "" {
					$LogRef_Attribute.$Tag3 = $LogRef_Tag3;
					$LogRef_Attribute.$Value3 = $LogRef_Value3;
				}
				SERIALIZE $LogRef_Attribute INTO $AttributeValue ;
				MBC_HIERCHMSGENV.SetAttribute $SessionId MessageId $MessageId Name SEBKORT_ATTRIBUTES.$SEBKort_LogRefAttribute Value $AttributeValue;
			}
			
			IF Arraysize($GenericRecord.$ref) > 0 {
				SERIALIZE $GenericRecord INTO $AttributeValue;
				MBC_HIERCHMSGENV.SetAttribute	$SessionId
									MessageId	$MessageId
									Name		SEBKORT_ATTRIBUTES.$Generic
									Value		$AttributeValue;
			}

		}

		/* Event: ErrorWriteOutput */
		WHEN $DMevent_ErrorWriteOutput {			
			IF $DM_event_debug { LOG "DMevent_ErrorWriteOutput" TYPE "DEBUG"; }
			
			#Extract all output errors into an Error record
			FOR $xI = 1 TO DMU.GetNrOfErrors() {

				DMU.GetError	$xI
					MAPOBJNAME	$MapObjName
					MAPOBJTYPE	$MapObjType
					ERROR		$ErrorText
					ERRORCODE	$ErrorCode
					DATATREEPATH $DTreePath;

				$ErrorRecords[$xI].$MapObjName = $MapObjName;
				$ErrorRecords[$xI].$MapObjType = $MapObjType;
				$ErrorRecords[$xI].$ErrorText = $ErrorText;
				$ErrorRecords[$xI].$ErrorCode = $ErrorCode;
				$ErrorRecords[$xI].$DTreePath = $DTreePath;

			}

			#Assign an Error attribute for further reporting back to partner.
			SERIALIZE $ErrorRecords INTO $ErrorRecordString;

			MBC_HIERCHMSGENV.SetAttribute $SessionId MessageId $MessageId Name SEBKORT_Attributes.$ErrorRecord Value $ErrorRecordString;		
			LOG "Number of output errors: " & DMU.GetNrOfErrors() TYPE "ERROR";
		}

		/* Event: BeforeAcsMethodCall */
		WHEN $DMevent_BeforeAcsMethodCall {
			IF $DM_event_debug { LOG "DMevent_BeforeAcsMethodCall" TYPE "DEBUG"; }
		}
		
		/* Event: AfterAcsMethodCall */
		WHEN $DMevent_AfterAcsMethodCall {
			IF $DM_event_debug { LOG "DMevent_AfterAcsMethodCall" TYPE "DEBUG"; }
		}
		
		/* Event: ErrorAcsMethodCall */
		WHEN $DMevent_ErrorAcsMethodCall {
			IF $DM_event_debug { LOG "DMevent_ErrorAcsMethodCall" TYPE "DEBUG"; }
		}
		
		/* Event: BeforeAcsReadInput */
		WHEN $DMevent_BeforeAcsReadInput {
			IF $DM_event_debug { LOG "DMevent_BeforeAcsReadInput" TYPE "DEBUG"; }
		}
		
		/* Event: AfterAcsReadInput */
		WHEN $DMevent_AfterAcsReadInput {
			IF $DM_event_debug { LOG "DMevent_AfterAcsReadInput" TYPE "DEBUG"; }
		}
		
		/* Event: ErrorAcsReadInput */
		WHEN $DMevent_ErrorAcsReadInput {
			IF $DM_event_debug { LOG "DMevent_ErrorAcsReadInput" TYPE "DEBUG"; }
		}
		
		/* Event: BeforeAcsWriteOutput */
		WHEN $DMevent_BeforeAcsWriteOutput {
			IF $DM_event_debug { LOG "DMevent_BeforeAcsWriteOutput" TYPE "DEBUG"; }
		}
		
		/* Event: AfterAcsWriteOutput */
		WHEN $DMevent_AfterAcsWriteOutput {
			IF $DM_event_debug { LOG "DMevent_AfterAcsWriteOutput" TYPE "DEBUG"; }
		}
		
		/* Event: AfterAcsWriteOutput */
		WHEN $DMevent_ErrorAcsWriteOutput {
				IF $DM_event_debug { LOG "DMevent_ErrorAcsWriteOutput" TYPE "DEBUG";}
		}
		
		/* Event: BeforeAcsEndMap */
		WHEN $DMevent_BeforeAcsEndMap {
			IF $DM_event_debug { LOG "DMevent_BeforeAcsEndMap" TYPE "DEBUG"; }
		}
		
		/* Event: AfterAcsEndMap */
		WHEN $DMevent_AfterAcsEndMap {
			IF $DM_event_debug { LOG "DMevent_AfterAcsEndMap" TYPE "DEBUG"; }
		}
		
		/* Event: ErrorAcsEndMap */
		WHEN $DMevent_ErrorAcsEndMap {
			IF $DM_event_debug { LOG "DMevent_ErrorAcsEndMap" TYPE "DEBUG"; }
		}
		
		/* Event: BeforeLogInput */
		WHEN $DMevent_BeforeLogInput {
			IF $DM_event_debug { LOG "DMevent_BeforeLogInput" TYPE "DEBUG"; }
		}
		
		/* Event: BeforeLogOutput */
		WHEN $DMevent_BeforeLogOutput {
			IF $DM_event_debug { LOG "DMevent_BeforeLogOutput" TYPE "DEBUG"; }
		}
		
		/* Event: SimulationStarted */
		WHEN $DMevent_SimulationStarted { 
			$Simulator = $True;
		}
		
		WHEN "DMevent_TimerAddWithCallback" {
			IF $DM_event_debug { LOG "DMevent_TimerAddWithCallback" TYPE "DEBUG"; }

			# $Data should contain three parts, separated with ":"
			# 1. The Timer Qualifier parameter
			# 2. The key of the Correlation in table server
			# 3. The timeout in seconds
			# 4. What level of logging should be done if timeout. LogError|LogWarning|LogInfo|NoLogging
			# 5. Error description in case of timeout
			# Typical call would be:
			# MBC_HIERCHMSGENV.CorrelationWrite $Id  Data MBC_HIERCHMSGENV.GetLoggerId($SessionId, $MessageId);
			# Main.Event "DMevent_TimerAddWithCallback" Data "Qual_AckTimeout:" & $Id & ":21600" & ":LogError" & ":" & $Description;
			
    	TRY {
    		$TimerData = SL_STRING.FieldExplode( $Data, ":" );
    	} CATCH $Exception
    	WHEN OTHERS {
				# Problems reading $Data, Return
				LOG "Problem parsing Event parameter $Data = " &  $Data TYPE "WARNING";
				RETURN;
    	}

			IF SL_STRING.FieldCount( $Data, ":" ) >= 5 {
				$TimerData = SL_STRING.FieldExplode( $Data, ":" );
				# Check that the timeout is only digits
				IF NOT NYTTO.ISNUMBER($TimerData[3]) { $TimerData[3] = "3600"; }
				MBC_HIERCHMSGENV.TimerAdd $TimerData[3]
 					Qualifier $TimerData[1]
 					Id $TimerData[2]
 					Callback SIDENT(CallbackLogAndCorrelationDelete)
 					UserData $Data;
 			} ELSE {
 				LOG "Insufficient parameters supplied in $Data = " & $Data TYPE "WARNING";
 			}
 		} # End WHEN "DMevent_TimerAddWithCallback"

		
		/* OTHER events not handled in any case above */
		WHEN OTHERS {
			IF $DM_event_debug { LOG "In event: " & $Event TYPE "DEBUG"; }
		}

		RETURN;
	}

	/*()----------------------------------------------------------------------------
	** CallbackLogAndCorrelationDelete log error and remove table entry after timeout 
	**----------------------------------------------------------------------------*/
    DECLARE STATEMENT CallbackLogAndCorrelationDelete
    		IN $qualifier PRIMITIVE
	  		Id IN $Id PRIMITIVE
	  		UserData IN $UserData PRIMITIVE
    {
    	DECLARE $lsStr[] STRING;
    	DECLARE $liErrorType INTEGER;
    	DECLARE $lrDataIO RECORD DATAIO.Handle;
    	DECLARE $lsLogid STRING;
    	DECLARE $liSessionId INTEGER;
    	DECLARE $lrLogEvent RECORD LOG_ENTRY.Event;

			# Userdata = Qual:Id:Timeout:LogType:Description
    	TRY {
    		$lsStr = SL_STRING.FieldExplode( $UserData, ":" );
    	} CATCH $Exception
    	WHEN OTHERS {
				# Problems reading UserData, default, delete correlation and log error.
				MBC_HIERCHMSGENV.CorrelationDelete $lsStr[2];
				LOG "Correlation " & $lsStr[2] & " removed after timeout expired. Problem parsing Userdata = " &  $UserData TYPE "ERROR";
				RETURN;
    	}
    	# Read and remove the correlation
    	TRY {
    		MBC_HIERCHMSGENV.CorrelationRead $Id Data $lsLogId;
    		$lsLogId = SL_STRING.FieldExtract($lsLogId, 1, ":" ); # Special handling of DKNETSPDF counting acks.
    		MBC_HIERCHMSGENV.CorrelationDelete $Id;
				LOG "Correlation " & $Id & " removed after timeout of " & $lsStr[3] & " sec expired. Userdata = " & $UserData TYPE "ERROR";
			} CATCH $Exception
    	WHEN OTHERS {
				# Problems deleting Correlation.
				LOG "Problems removing Correlation with id " & $Id & " after " & $lsStr[3] & " seconds. Userdata = " & $UserData TYPE "WARNING";
			}
			# Log in MsgLog
			CASE $lsStr[4]
			WHEN "LogError" 	{ $liErrorType = LOG_ENTRY.$Event_SeverityError; }
			WHEN "LogWarning"	{ $liErrorType = LOG_ENTRY.$Event_SeverityWarning; }
			WHEN "LogInfo" 		{ $liErrorType = LOG_ENTRY.$Event_SeverityInfo; }
			WHEN OTHERS				{ $liErrorType = LOG_ENTRY.$Event_SeverityWarning; } # Default...

			DATAIO.AttachString $lrDataIO String "hello world";
			$liSessionId = MBC_HIERCHMSGENV.CreateSession($lrDataIO);

			$lrLogEvent.$Description = $lsStr[5];
			$lrLogEvent.$Code = 1;
			$lrLogEvent.$Severity = $liErrorType;
			$lrLogEvent.$Date = CurrentDate();
			MBC_HIERCHMSGENV.CreateLoggerEvent $liSessionId
            LoggerId    $lsLogId
            Event       $lrLogEvent;

			MBC_HIERCHMSGENV.StartSession $liSessionId;

			RETURN;
    } # End CallbackLogAndCorrelationDelete

 	/*()----------------------------------------------------------------------------
	** AddMapOutputNameAttribute
	** Description: Add output name attribute. Needed in the B2Bi runtime environment, 
	** this to be able to diffrentiate different outputs from each others. 
	** The addition of the attribute is only needed in maps having 
	** multiple different output objects. 
	**----------------------------------------------------------------------------*/
	DECLARE STATEMENT AddMapOutputNameAttribute  {
		
		DECLARE $SessionId	INTEGER; 
		DECLARE $MessageId	INTEGER; 
		DECLARE $OutputName	STRING; 

		$OutputName = DMRTM.GetCurrentMapObjName(); 

		DMRTM.GetCurrentMessageId $SessionId MessageId $MessageId; 

		IF $DM_debug = $True { LOG FORMAT("CIP_MapOutputNameAttributeValue = %s", $OutputName) TYPE "DEBUG"; } 

		MBC_HIERCHMSGENV.SetAttribute $SessionId MessageId $MessageId Name "MAP_STAGE_OUTPUT_NAME" Value $OutputName; 

		RETURN; 

	}

	/*()----------------------------------------------------------------------------
	** Info
	**----------------------------------------------------------------------------*/
	DECLARE PUBLIC STATEMENT Info	OUT $name			PRIMITIVE 
						DESCRIPTION	OUT $description 	PRIMITIVE
						VERSION		OUT $version		PRIMITIVE
						SIMULATION	OUT $simulation		PRIMITIVE
						CONVERSION	OUT $conversion		PRIMITIVE {

		%INFOCODE

		RETURN;
	}

	/*()----------------------------------------------------------------------------
	** MODULE_CLEAN
	**----------------------------------------------------------------------------*/
	DECLARE STATEMENT MODULE_CLEAN {
		Destroy;
		RETURN;
	 }
	 
  
}
