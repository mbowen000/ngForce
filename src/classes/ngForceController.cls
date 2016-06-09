global class ngForceController {

	/*
	* Modified Version of RemoteTKController
	*/

	global class picklistValues {
		String label {get; set;}
		String value {get; set;}
	}

	global class Select2Data {
		@TestVisible String id               {get; set;}
		@TestVisible String name             {get; set;}
		@TestVisible String searchName {get; set;}
	}

	global class QueryString {
		@TestVisible String selectClause {get; set;}
		@TestVisible String fromClause {get; set;}
	}

	private static String makeError(String message, String errorCode) {
		JSONGenerator gen = JSON.createGenerator(false);
		gen.writeStartArray();
		gen.writeStartObject();
		gen.writeStringField('message', message);
		gen.writeStringField('errorCode', errorCode);
		gen.writeEndObject();
		gen.writeEndArray();

		return gen.getAsString();
	}

	private static String writeFields(String objtype, SObject obj, String fields) {
		Map<String, Object> fieldMap = null;
		try {
			fieldMap = (Map<String, Object>)JSON.deserializeUntyped(fields);
			fieldMap.remove('attributes');
		} catch (JSONException je) {
			return makeError(je.getMessage(), 'JSON_PARSER_ERROR');
		}

		Schema.SObjectType targetType = Schema.getGlobalDescribe().get(objtype);

		Map<String, Schema.sObjectField> targetFields = targetType.getDescribe().fields.getMap();

		try {
			for (String key : fieldMap.keySet()) {
				if (targetFields.get(key) == null) {
					system.debug('[{"message":"Field ' + key + ' does not exist on object type ' + objtype + '","errorCode":"INVALID_FIELD"}]');
					return '[{"message":"Field ' + key + ' does not exist on object type ' + objtype + '","errorCode":"INVALID_FIELD"}]';
				}

				Object value = fieldMap.get(key);
				Schema.DisplayType valueType = targetFields.get(key).getDescribe().getType();

				if (value != null && value instanceof String && valueType != Schema.DisplayType.String) {
					// Coerce an incoming String to the correct type
					String svalue = (String)value;

					if (valueType == Schema.DisplayType.Date) {
						system.debug('doing ' + key + ' : ' + svalue);
						obj.put(key, Date.valueOf(svalue));
					} else if ( valueType == Schema.DisplayType.DateTime) {
						obj.put(key, DateTime.valueOf(svalue));
					} else if (valueType == Schema.DisplayType.Percent ||
							valueType == Schema.DisplayType.Currency) {
						obj.put(key, svalue == '' ? null : Decimal.valueOf(svalue));
					} else if (valueType == Schema.DisplayType.Double) {
						obj.put(key, svalue == '' ? null : Double.valueOf(svalue));
					} else if (valueType == Schema.DisplayType.Integer) {
						obj.put(key, Integer.valueOf(svalue));
					} else if (valueType == Schema.DisplayType.Base64) {
						obj.put(key, EncodingUtil.base64Decode(svalue.split(',')[1]));
					} else {
						obj.put(key, svalue);
					}
				} else {
					// Just try putting the incoming value on the object
					obj.put(key, value);
				}
			}
		} catch (SObjectException soe) {
			system.debug(soe.getMessage() + 'INVALID_FIELD');
			return makeError(soe.getMessage(), 'INVALID_FIELD');
		}

		return null;
	}

	@remoteAction
	global static String describe(String objtype) {
		// Just enough to make the sample app work!
		Schema.SObjectType targetType = Schema.getGlobalDescribe().get(objtype);
		if (targetType == null) {
			return '[{"message":"The requested resource does not exist","errorCode":"NOT_FOUND"}]';
		}

		Schema.DescribeSObjectResult sobjResult = targetType.getDescribe();

		Map<String, Schema.SObjectField> fieldMap = sobjResult.fields.getMap();

		List<Object> fields = new List<Object>();
		for (String key : fieldMap.keySet()) {
			Schema.DescribeFieldResult descField = fieldMap.get(key).getDescribe();
			Map<String, Object> field = new Map<String, Object>();

			field.put('type', descField.getType().name().toLowerCase());
			field.put('name', descField.getName());
			field.put('label', descField.getLabel());
			List<String> references = new List<String>();
			for (Schema.sObjectType t : descField.getReferenceTo()) {
				references.add(t.getDescribe().getName());
			}
			if (!references.isEmpty()) {
				field.put('referenceTo', references);
			}

			fields.add(field);
		}

		Map<String, Object> result = new Map<String, Object>();
		result.put('fields', fields);

		return JSON.serialize(result);
	}

	/*
	 * These methods are available only after you have established a fieldset
	 * on an object.
	@remoteAction
	global static String describeFieldSet(String objtype, String fieldSetName) {
	Schema.SObjectType token = Schema.getGlobalDescribe().get(objtype);
	Schema.DescribeSObjectResult dr = token.getDescribe();
	Map<String, Schema.FieldSet> FsMap = dr.fieldSets.getMap();
	return JSON.serialize(FsMap.get(FieldSetName).getFields());
	}

	@remoteAction
	global static String describeField(String objtype, String fieldName) {
	Schema.SObjectType token = Schema.getGlobalDescribe().get(objtype);
	Schema.DescribeSObjectResult dr = token.getDescribe();
	Schema.DescribeFieldResult fieldDescribe = dr.fields.getMap().get(fieldName).getDescribe();
	return JSON.serialize(fieldDescribe);
	}

	@remoteAction
	global static String soqlFromFieldSet(String objtype, String fieldSetName) {
	Schema.SObjectType token = Schema.getGlobalDescribe().get(objtype);
	Schema.DescribeSObjectResult dr = token.getDescribe();
	Map<String, Schema.FieldSet> FsMap = dr.fieldSets.getMap();
	String selectClause = 'SELECT Id';
	Set<Schema.FieldSetMember> querySet = new Set<Schema.FieldSetMember>();
	querySet.addAll(FsMap.get(FieldSetName).getFields());
	for (Schema.FieldSetMember f : querySet) {
	  selectClause += ', ' + f.getFieldPath();
	}
	String fromClause = ' FROM ' + dr.getName();
	QueryString qs = new QueryString();
	qs.selectClause = selectClause;
	qs.fromClause = fromClause;
	return JSON.serialize(qs);
	}

	@remoteAction
	global static String queryFromFieldSet(String id, String fieldSetName) {
	Id objId = (id) Id;
	Schema.SObjectType token = objId.getSObjectType();
	Schema.DescribeSObjectResult dr = token.getDescribe();
	Map<String, Schema.FieldSet> FsMap = dr.fieldSets.getMap();
	String queryString = 'SELECT Id';
	List<Schema.FieldSetMember> querySet = new List<Schema.FieldSetMember>();
	querySet = FsMap.get(FieldSetName).getFields();
	for (Schema.FieldSetMember f : querySet) {
	  queryString += ', ' + f.getFieldPath();
	}
	queryString += ' FROM ' + dr.getName() + ' WHERE id = \'' + objId + '\' LIMIT 1';
	system.debug(queryString);
	return JSON.serialize(database.Query(queryString));
	}
	*/
	@remoteAction
	global static List<pickListValues> getPicklistValues(String objtype, String fieldName) {
		Schema.SObjectType token = Schema.getGlobalDescribe().get(objtype);
		Schema.DescribeSObjectResult dr = token.getDescribe();
		Map<String, Schema.SObjectField> field_map = dr.fields.getMap();
		List<Schema.PicklistEntry> pickListValues = field_map.get(fieldName).getDescribe().getPickListValues();
		List<pickListValues> options = new List<picklistValues>();
		for (Schema.PicklistEntry plv : pickListValues) {
			pickListValues pv = new pickListValues();
			pv.label = plv.getLabel();
			pv.value = plv.getValue();
			options.add(pv);
		}
		return options;
	}

	@remoteAction
	global static String getQueryResultsAsSelect2Data(String soql) {
		List<sObject> records;
		try {
			records = Database.query(soql);
			system.debug('somehow passed ' + records);
		} catch (QueryException qe) {
			system.debug('caught query exception');
			return makeError(qe.getMessage(), 'INVALID_QUERY');
		} catch (Exception e) {
			system.debug('caught exception');
			return makeError(e.getMessage(), 'INVALID_QUERY');
		}
		List<Select2Data> sData = new List<Select2Data>();
		for (sObject r : records) {
			Select2Data s = new Select2Data();
			s.id = r.id;
			s.name = (String) r.get('Name');
			//s.searchName = (String) r.get('SearchName__c');
			sData.add(s);
		}
		return JSON.serialize(sData);
	}

	@remoteAction
	global static String sObjectKlone(String iId) {
		Id id = (id) iId;
		sObjectType type = id.getSObjectType();
		Schema.DescribeSObjectResult dr = type.getDescribe();
		map<String, Schema.SObjectField> fieldMap = dr.fields.getMap();
		String qs = 'SELECT Id';
		Set<string> querySet = new Set<string>();
		querySet.addAll(fieldMap.keySet());
		querySet.remove('id');
		for (String f : querySet) {
			//Skip compound address fields
			if (f.contains('address')) {
				continue;
			}
			
			qs += ', ' + f;
		}
		qs += ' FROM ' + dr.getName() + ' WHERE id = \'' + id + '\' LIMIT 1';
		sObject toClone = Database.query(qs);
		sObject cloned = toClone.clone(false, true, false, false);
		String results;
		try {
			upsert cloned;
			results = cloned.id;
		} catch (DMLException e) {
			system.debug(e);
			results = e.getMessage();
		}
		return JSON.serialize(results);
	}

	@remoteAction
	global static String getObjType(String Id) {
		Id objId = (id) Id;
		Schema.SObjectType token = objId.getSObjectType();
		Schema.DescribeSObjectResult dr = token.getDescribe();
		String objName = dr.getName();
		Map<String, String> retObj = new Map<String, String>();
		retObj.put('type', objName);
		return JSON.serialize(retObj);
	}

	@remoteAction
	global static Map<String, Object> create(String objtype, String fields) {

		Schema.SObjectType targetType = Schema.getGlobalDescribe().get(objtype);
		if (targetType == null) {
			Map<String,Object> err = new Map<String, Object>();
			err.put('message', 'The requested resource does not exist');
			err.put('errorCode', 'NOT_FOUND');
			return err;
		}

		Map<String, Schema.sObjectField> targetFields = targetType.getDescribe().fields.getMap();

		SObject obj = targetType.newSObject();

		Map<String, Object> fieldMap = null;

		String error = writeFields(objType, obj, fields);
		if (error != null) {
			Map<String,Object> err = new Map<String, Object>();
			err.put('message', error);
			err.put('errorCode', 'ERROR_WRITING_FIELDS');
			return err;
		}

		try {
			insert obj;
		} catch (DMLException dmle) {
			String fieldNames = '';
			for (String field : dmle.getDmlFieldNames(0)) {
				if (fieldNames.length() > 0) {
					fieldNames += ',';
				}
				fieldNames += '"' + field + '"';
			}
			//return '[{"fields":[' + fieldNames + '],"message":"' + dmle.getDmlMessage(0) + '","errorCode":"' + dmle.getDmlType(0).name() + '"}]';
			Map<String,Object> err = new Map<String, Object>();
			err.put('message', dmle.getDmlMessage(0));
			err.put('errorCode', dmle.getDmlType(0).name());
			return err;
		}

		Map<String, Object> result = new Map<String, Object>();
		result.put('id', obj.id);
		result.put('errors', new List<String>());
		result.put('success', true);

		//return JSON.serialize(result);
		return result;
	}

	@remoteAction
	global static Map<String, Object> bulkCreate(String objtype, String fields) {
		Schema.SObjectType targetType = Schema.getGlobalDescribe().get(objtype);
		Map<String, Schema.sObjectField> targetFields = targetType.getDescribe().fields.getMap();
		if (targetType == null) {
			//return '[{"message":"The requested resource does not exist","errorCode":"NOT_FOUND"}]';
			Map<String, Object> message = new Map<String,Object>();
			message.put('message', 'The requested resource does not exist');
			return message;
		}

		List<sObject> objs = new List<sObject>();

		Map<String, Object> incomingFieldJsonObject = null;
		try {
			incomingFieldJsonObject = (Map<String, Object>)JSON.deserializeUntyped(fields);
		} catch (JSONException je) {
			//return '[{"message":"' + je.getMessage() + '","errorCode":"JSON_PARSER_ERROR"}]';
			Map<String, Object> message = new Map<String,Object>();
			message.put('message', je.getMessage());
			return message;
		}

		try {
			for (String row : incomingFieldJsonObject.keySet()) {
				Map<String, Object> current = (Map<String, Object>) incomingFieldJsonObject.get(row);
				SObject obj = targetType.newSObject();
				for (String property : current.keySet()) {
					if (targetFields.get(property).getDescribe().getType() == Schema.DisplayType.Date) {
						obj.put(property, Date.valueOf((String)current.get(property)));
					} else if ( targetFields.get(property).getDescribe().getType() == Schema.DisplayType.DateTime) {
						obj.put(property, DateTime.valueOf((String)current.get(property)));
					} else if (targetFields.get(property).getDescribe().getType() == Schema.DisplayType.Percent ||
							targetFields.get(property).getDescribe().getType() == Schema.DisplayType.Currency) {
						obj.put(property, String.valueOf(current.get(property)) == '' ? null : Decimal.valueOf((String)current.get(property)));
					} else if (targetFields.get(property).getDescribe().getType() == Schema.DisplayType.Double) {
						obj.put(property, String.valueOf(current.get(property)) == '' ? null : Double.valueOf(current.get(property)));
					} else if (targetFields.get(property).getDescribe().getType() == Schema.DisplayType.Integer) {
						obj.put(property, Integer.valueOf(current.get(property)));
					} else {
						obj.put(property, current.get(property));
					}
				}
				objs.add(obj);
			}
		} catch (SObjectException soe) {
			//return '[{"message":"' + soe.getMessage() + '","errorCode":"INVALID_FIELD"}]';
			Map<String, Object> message = new Map<String,Object>();
			message.put('message', soe.getMessage());
			return message;
		}

		try {
			insert objs;
		} catch (DMLException dmle) {
			String fieldNames = '';
			for (String field : dmle.getDmlFieldNames(0)) {
				if (fieldNames.length() > 0) {
					fieldNames += ',';
				}
				fieldNames += '"' + field + '"';
			}
			//return '[{"fields":[' + fieldNames + '],"message":"' + dmle.getDmlMessage(0) + '","errorCode":"' + dmle.getDmlType(0).name() + '"}]';
			// todo: re-create level of detail about which insert failed like before
			Map<String, Object> message = new Map<String,Object>();
			message.put('message', dmle.getDmlMessage(0));
			return message;
		}

		List<Id> rids = new List<Id>();
		for (sObject o : objs) {
			rids.add(o.Id);
		}

		Map<String, Object> result = new Map<String, Object>();
		result.put('id', rids);
		result.put('errors', new List<String>());
		result.put('success', true);

		return result;
	}

	/**
	 * Perform a bulk update operation for a JSON array of SObjects.
	 * @param  objtype    SObject name e.g. "Account"
	 * @param  jsonObjArr Array of SObject field data that should include the ID
	 * @return JSON array of the records that have successfully been updated.
	 */
	@remoteAction global static String bulkUpdate(String objtype, String jsonObjArr) {
		Type listType = Type.forName('List<' + objType + '>');
		if (listType == null) {
			return makeError('The requested resource does not exist', 'NOT_FOUND');
		}

		List<SObject> objs;
		try {
			objs = (List<SObject>)JSON.deserialize(jsonObjArr, listType);
		} catch (JSONException je) {
			return makeError('Unable to deserialize the JSON data array', 'INVALID_JSON');
		}

		try {
			update objs;
		} catch (DMLException dmle) {
			return makeError(dmle.getMessage(), 'DML_ERROR');
		}

		List<Id> rids = new List<Id>();
		for (sObject o : objs) {
			rids.add(o.Id);
		}

		Map<String, Object> result = new Map<String, Object>();
		result.put('id', rids);
		result.put('errors', new List<String>());
		result.put('success', true);

		return JSON.serialize(result);
	}

	/**
	 * Perform a bulk upsert operation for a JSON array of SObjects.
	 * @param  objtype    SObject name e.g. "Account"
	 * @param  jsonObjArr Array of SObject field data that should include the ID
	 * @return JSON array of the records that have successfully been updated.
	 */
	@remoteAction global static String bulkUpsert(String objtype, String jsonObjArr) {
		Map<String, Object> message = new Map<String,Object>();
		Type listType = Type.forName('List<' + objType + '>');
		if (listType == null) {
			message.put('message', 'The requested resource does not exist');
			return JSON.serialize(message);
		}

		List<SObject> objs;
		List<Object> objsUntyped;
		try {
			objs = (List<SObject>)JSON.deserialize(jsonObjArr, listType);
			objsUntyped = (List<Object>)JSON.deserializeUntyped(jsonObjArr);
		} catch (JSONException je) {
			message.put('message', 'Unable to deserialize the JSON data array');
			return JSON.serialize(message);
		}

		try {
			upsert objs;
		} catch (DMLException dmle) {
			message.put('message', dmle.getMessage());
			return JSON.serialize(message);
		}

		List<Id> rids = new List<Id>();
		for (sObject o : objs) {
			rids.add(o.Id);
		}

		// get the fields that were written as a default
		// todo: we can probably pass the fields ilst optionally for more retrival (like formulas)
		Schema.SObjectType sobjtype = Schema.getGlobalDescribe().get(objType);
		Map<String, Schema.SObjectField> fieldDescMap = sobjtype.getDescribe().fields.getMap();

		List<string> fieldsList = new List<String>();
		List<sObject> updatedObjs = new List<sObject>();

//		for(Schema.SObjectField sfield : fieldDescMap.values()) {
//            Schema.describefieldresult dfield = sfield.getDescribe();
//			System.debug(dfield);
//			if(dfield.isUpdateable() || dfield.isCalculated() || dfield.isAutoNumber()) {
//				System.debug('passed');
//				fieldsList.add(dfield.getName());
//			}
//        }
		// we'll only get the fields that are in the request
		Map<String, Object> fieldsUntyped = (Map<String,Object>)objsUntyped.get(0);
		fieldsList = new List<String>(fieldsUntyped.keySet());

		System.debug(fieldsList);

		String fieldsString = String.join(fieldsList, ', ');
		String idsString = '\'' + String.join(rids, '\', \'') + '\'';
		String q = 'SELECT ' + fieldsString + ' FROM ' + objType + ' WHERE Id IN (' + idsString + ')';
		System.debug('Query: ' + q);

		Map<String, Object> result = new Map<String, Object>();
		updatedObjs = Database.query(q);
		System.debug(updatedObjs);

		result.put('id', rids);
		result.put('updated', updatedObjs);
		result.put('errors', new List<String>());
		result.put('success', true);

		return JSON.serialize(result);
	}

	/**
	 * Perform a bulk delete operation for a JSON array of SObjects.
	 * @param  objtype    SObject name e.g. "Account"
	 * @param  jsonObjArr Array of SObject field data that should include the ID
	 * @return JSON array of the records that have successfully been updated.
	 */
	@remoteAction global static Map<String, Object> bulkDelete(String objtype, String jsonObjArr) {
		Map<String, Object> message = new Map<String,Object>();
		Type listType = Type.forName('List<' + objType + '>');
		if (listType == null) {
			message.put('message', 'The requested resource does not exist');
			return message;
		}

		List<SObject> objs;
		try {
			objs = (List<SObject>)JSON.deserialize(jsonObjArr, listType);
		} catch (JSONException je) {
			message.put('message', 'Unable to deserialize the JSON data array');
			return message;
		}

		try {
			delete objs;
		} catch (DMLException dmle) {
			message.put('message', dmle.getMessage());
			return message;
		}

		Map<String, Object> result = new Map<String, Object>();
		result.put('errors', new List<String>());
		result.put('success', true);

		return result;
	}

	@remoteAction
	global static String retrieve(String objtype, String id, String fieldlist) {
		Boolean containsId = false;
		for (String field : fieldlist.split(',')) {
			if (field.equalsIgnoreCase('id')) {
				containsId = true;
				break;
			}
		}

		if (!containsId) {
			fieldlist = 'Id,' + fieldlist;
		}

		String soql = 'SELECT ' + fieldlist + ' FROM ' + objtype + ' WHERE Id = \'' + id + '\'';
		List<sObject> records;
		try {
			records = Database.query(soql);
		} catch (QueryException qe) {
			return '[{"message":"' + qe.getMessage() + '","errorCode":"INVALID_QUERY"}]';
		}

		return JSON.serialize(records[0]);
	}

	@remoteAction
	global static Map<String,Object> upser(String objtype, String externalIdField, String externalId, String fields) {
		Schema.SObjectType targetType = Schema.getGlobalDescribe().get(objtype);

		SObject obj = targetType.newSObject();
		obj.put(externalIdField, externalId);

		Map<String, Object> fieldMap =
				(Map<String, Object>)JSON.deserializeUntyped(fields);
		for (String key : fieldMap.keySet()) {
			obj.put(key, fieldMap.get(key));
		}

		Schema.SObjectField sobjField = targetType.getDescribe().fields.getMap().get(externalIdField);

		try {
			Database.Upsert(obj, sobjField);
			Map<String,Object> response = new Map<String,Object>();
			response.put('success', true);
			response.put('objectCreated', obj);
		}
		catch(Exception e) {
			Map<String,Object> error = new Map<String,Object>();
			error.put('message', e.getMessage());
			error.put('errorCode', 'ERROR_DURING_UPSERT');
			return error;
		}

		Map<String,Object> response = new Map<String,Object>();
		response.put('success', true);
		response.put('objectCreated', obj);
		return response;
	}

	@remoteAction
	global static String updat(String objtype, String id, String fields) {
		Schema.SObjectType targetType = Schema.getGlobalDescribe().get(objtype);
		if (targetType == null) {
			return '[{"message":"The requested resource does not exist","errorCode":"NOT_FOUND"}]';
		}

		SObject obj = targetType.newSObject(id);

		Map<String, Object> fieldMap = null;

		String error = writeFields(objType, obj, fields);
		if (error != null) {
			return error;
		}

		try {
			update obj;
		} catch (DMLException dmle) {
			String fieldNames = '';
			for (String field : dmle.getDmlFieldNames(0)) {
				if (fieldNames.length() > 0) {
					fieldNames += ',';
				}
				fieldNames += '"' + field + '"';
			}
			system.debug('[{"fields":[' + fieldNames + '],"message":"' + dmle.getDmlMessage(0) + '","errorCode":"' + dmle.getDmlType(0).name() + '"}]');
			return '[{"fields":[' + fieldNames + '],"message":"' + dmle.getDmlMessage(0) + '","errorCode":"' + dmle.getDmlType(0).name() + '"}]';
		}

		return null;
	}

	@remoteAction
	global static String del(String objtype, String id) {
		Schema.SObjectType targetType = Schema.getGlobalDescribe().get(objtype);
		if (targetType == null) {
			return '[{"message":"The requested resource does not exist","errorCode":"NOT_FOUND"}]';
		}

		SObject obj = targetType.newSObject(id);

		try {
			delete obj;
		} catch (DMLException dmle) {
			String fieldNames = '';
			for (String field : dmle.getDmlFieldNames(0)) {
				if (fieldNames.length() > 0) {
					fieldNames += ',';
				}
				fieldNames += '"' + field + '"';
			}
			return '[{"fields":[' + fieldNames + '],"message":"' + dmle.getDmlMessage(0).trim() + '","errorCode":"' + dmle.getDmlType(0).name() + '"}]';
		}

		return null;
	}

	@remoteAction
	global static String query(String soql) {
		List<sObject> records;
		try {
			records = Database.query(soql);
		} catch (QueryException qe) {
			return '[{"message":"' + qe.getMessage() + '","errorCode":"INVALID_QUERY"}]';
		}

		Map<String, Object> result = new Map<String, Object>();
		result.put('records', records);
		result.put('totalSize', records.size());
		result.put('done', true);

		return JSON.serialize(result);
	}

	@remoteAction
	global static String search(String sosl) {
		system.debug('$$$$$$$$$' + sosl);
		List<List<SObject>> result;
		try {
			result = Search.query(sosl);
		} catch (SearchException se) {
			return '[{"message":"' + se.getMessage() + '","errorCode":"INVALID_SEARCH"}]';
		} catch (Exception e) {
			system.debug('$$$$$$$$$$$' + e.getCause());
			return '[{"message":"' + e.getMessage() + '","errorCode":"INVALID_SEARCH"}]';
		}

		return JSON.serialize(result);
	}

}