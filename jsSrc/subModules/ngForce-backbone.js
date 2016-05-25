/*
 
*/

(function(window, document, undefined) {
  'use strict';

  angular.module('ngForce', []).
    /*
      @chalk
      @name Backbone factory
      @description
      To make Backbone work properly with AngularJS, ng-backbone overrides Backbone's sync and ajax methods.
    */
    factory('Backbone', ['$http','vfr', function($http, vfr) {
      var methodMap, sync, ajax, buildQueryString, isUndefined = _.isUndefined;

      methodMap = {
        create: 'POST',
        update: 'PUT',
        patch: 'PATCH',
        delete: 'DELETE',
        read: 'GET'
      };

      sync = function(method, model, options) {
        // Default options to empty object
        if (isUndefined(options)) {
          options = {};
        }

        var httpMethod = options.method || methodMap[method],
            params = {method: httpMethod};

        if (!options.url) {
          params.url = _.result(model, 'url');
        }

        if (isUndefined(options.data) && model && (httpMethod === 'POST' || httpMethod === 'PUT' || httpMethod === 'PATCH')) {
          params.data = JSON.stringify(options.attrs || model.toJSON(options));
        }

        // AngularJS $http doesn't convert data to querystring for GET method
        if (httpMethod === 'GET' && !isUndefined(options.data)) {
          params.params = options.data;
        }
        if(httpMethod === 'GET') {
          params.query = _.result(model, 'getQueryString');

          // in the callback we will return the data
          var xhr = vfr.query(params.query).then(function(results) {
          
            if(!isUndefined(options.success) && _.isFunction(options.success)) {
              options.success(results.records);
            }
          
          }).catch(function(err) {
          
            options.error(err);
          
          }).finally(function() {

          });
        }

        
        /*
        var xhr = ajax(_.extend(params, options)).
          success(function(data, status, headers, config) {
            options.xhr = {
              status: status,
              headers: headers,
              config: config
            };

            if (!isUndefined(options.success) && _.isFunction(options.success)) {
              options.success(data);
            }
          }).
          error(function(data, status, headers, config) {
            options.xhr = {
              status: status,
              headers: headers,
              config: config
            };

            if (!isUndefined(options.error) && _.isFunction(options.error)) {
              options.error(data);
            }
          });
        */

        model.trigger('request', model, xhr, _.extend(params, options));

        return xhr;
      };

      /*
        @chalk
        @private
        @name ajax
        @description
        Making ajax request
      */
      ajax = function() {
        return $http.apply($http, arguments);
      };

      buildQueryString = function(fields, objectName) {

        // todo: refactor this to be recursive -- should be able to go infinite levels deep building subqueries - even though salesforce wont!
        var process = function(value, index, list) {
          if(!value.relationship) {
            return value.name;
          }
          else {
            // should return (SELECT Model.fields FROM Model.objectType)
            return '(SELECT ' + _.pluck(value.collection.prototype.model.prototype.fields, 'name').join(', ') + ' FROM ' + value.collection.prototype.name + ')';
          }
        }

        return 'SELECT ' + _.map(fields, process).join(', ') + ' FROM ' + objectName;
        //todo add filters, etc.
      }

      return _.extend(Backbone, {
        sync: sync,
        ajax: ajax,
        buildQueryString: buildQueryString
      });
    }]).

    /*
      @chalk
      @name NgBackboneModel
      @description
      Base NgBackbone model extends Backbone.model by adding additional properties and functions, including `$attributes` and `$status`. When overriding NgBackboneModel `set` method but you would like to keep `$attributes`, you'll have to explicitly call NgBackboneModel set:
      ```javascript
      var Sample = NgBackboneModel.extend({
        set: function(key, val, options) {
          NgBackboneModel.prototype.set.apply(this, arguments);
        }
      });
      ```

      In rare cases when you want to override the constructor which allows you to replace the actual constructor function for your model, you should invoke NgBackboneModel constructor in the end.
      ```javascript
      var Sample = NgBackboneModel.extend({
        constructor: function() {
          this.text = 'Sample!';
          NgBackboneModel.apply(this, arguments);
        }
      });
      ```

      The `$attributes` property allows application to use AngularJS two-way binding to manipulate Backbone objects using Backbone `get` and `set`.
      HTML:
      ```html
      <input type="text" ng-model="person.$attributes.name">
      ```

      Javascript:
      ```javascript
      $scope.person = new Person({
        name: 'John'
      });
      ```

      The `$status` property is the hash containing model sync state. Since `$status` updates using Backbone event, passing `{silent: true}` will prevent `$status` from updating. `$status` contains four properties, including:
      - `deleting`: Set to true when invoking `destroy` method on model (HTTP `DELETE` request)
      - `loading`:  Set to true when fetching model data from server (HTTP `GET` request)
      - `saving`:   Set to true when creating or updating model (HTTP `POST` or `PUT` request)
      - `syncing`:  Set to true whenever a model has started a request to the server

      HTML:
      ```html
      <span ng-if="user.$status.loading">Loading</span>
      <label>{{user.name}}</label>
      ```

      Javascript:
      ```javascript
      $scope.user = new User({id: '123'});
      $scope.user.fetch();
      ```
    */
    factory('NgBackboneModel', ['$rootScope', 'Backbone', function($rootScope, Backbone) {
      var defineProperty;

      defineProperty = function(key) {
        var self = this;
        Object.defineProperty(this.$attributes, key, {
          enumerable: true,
          configurable: true,
          get: function() {
            return self.get(key);
          },
          set: function(newValue) {
            self.set(key, newValue);
          }
        });
      };

      return Backbone.Model.extend({

        fields: [{
          name: 'Id'
        }],

        // override this
        objectType: 'Account',

        // todo: call that gets sobjects describe information and turns into fields[] array above

        getQueryString: function() {
          // todo: figure out how to call this
          return Backbone.buildQueryString(this.prototype.fields, this.prototype.objectType);
        },

        createSubModels: function(results) {
          console.log(results);
        },

        constructor: function NgBackboneModel() {
          this.$status = {
            deleting: false,
            loading:  false,
            saving:   false,
            syncing:  false
          };

          this.on('request', function(model, xhr, options) {
            this.$setStatus({
              deleting: (options.method === 'DELETE'),
              loading:  (options.method === 'GET'),
              saving:   (options.method === 'POST' || options.method === 'PUT'),
              syncing:  true
            });
          });

          this.on('sync', this.createSubModels);

          this.on('sync error', this.$resetStatus);

          return Backbone.Model.apply(this, arguments);
        },

        initialize: function(options) {
          var self = this;
          _.map(this.fields, function(field, index) {
            console.log(field);
            if(field.relationship && field.relationship === 'OneToMany') {
              var recordset = self.get(field.collection.prototype.name);
              if(recordset) {
                self.set(field.collection.prototype.name, new field.collection(self.get(field.collection.prototype.name).records));
              }
              else {
                self.set(field.collection.prototype.name, new field.collection([]));
              }
              
            }
          });

          return Backbone.Model.prototype.initialize.apply(this, arguments);
        },

        set: function(key, val, options) {
          var output = Backbone.Model.prototype.set.apply(this, arguments);

          // Do not set binding if attributes are invalid
          if (output) {
            this.$setBinding(key, val, options);
          }

          return output;
        },

        /*
          @chalk
          @name $resetStatus
          @description
          Reset all properties on `$status` including `deleting`, `loading`, `saving`, and `syncing` back to false
        */
        $resetStatus: function() {
          return this.$setStatus({
            deleting: false,
            loading:  false,
            saving:   false,
            syncing:  false
          });
        },

        /*
          @chalk
          @private
          @name setBinding
          @description
          Add binding on `$attributes` to a key on `attributes`
        */
        $setBinding: function(key, val, options) {
          var attr, attrs, unset;

          if (_.isUndefined(key)) {
            return this;
          }

          if (_.isObject(key)) {
            attrs = key;
            options = val;
          } else {
            (attrs = {})[key] = val;
          }

          options = options || {};

          if (_.isUndefined(this.$attributes)) {
            this.$attributes = {};
          }

          unset = options.unset;

          for (attr in attrs) {
            if (unset && this.$attributes.hasOwnProperty(attr)) {
              delete this.$attributes[attr];
            } else if (!unset && !this.$attributes[attr]) {
              defineProperty.call(this, attr);
            }
          }

          return this;
        },

        /*
          @chalk
          @name $setStatus
          @description
          Update model status on `$status`

          @param {Object} attributes Set one or multiple statuses
          @param {Object} options Options
        */
        $setStatus: function(key, value, options) {
          var attr, attrs;

          if (_.isUndefined(key)) {
            return this;
          }

          if (_.isObject(key)) {
            attrs = key;
            options = value;
          } else {
            (attrs = {})[key] = value;
          }

          options = options || {};

          for (attr in this.$status) {
            if (attrs.hasOwnProperty(attr) && _.isBoolean(attrs[attr])) {
              this.$status[attr] = attrs[attr];
            }
          }
        },

        $removeBinding: function(attr, options) {
          return this.$setBinding(attr, void 0, _.extend({}, options, {unset: true}));
        }
      });
    }]).

    /*
      @chalk
      @name NgBackboneCollection
      @description
      Base NgBackbone collection extends Backbone.collection by adding additonal properties and functions, such as `$models` and `$status`.

      Similar to NgBackboneModel, in rare cases where you may want to override the constructor, you should invoke NgBackboneCollection in the end.
      ```javascript
      var SampleCollection = NgBackboneCollection.extend({
        constructor: function(models, options) {
          this.allSamples = false;

          NgBackboneCollection.apply(this, arguments);
        }
      });
      ```

      The `$models` property creates a one-way binding to collection `models` which is the Javascript array of models. Application can only access the array with `$models` but will not be able to modify it.
      HTML:
      ```html
      <ul>
        <li ng-repeat="user in users.$models">{{user.username}}<li>
      </ul>
      ```

      Javascript:
      ```
      $scope.users = new Users();
      $scope.users.fetch();
      ```

      The `$status` property is the hash containing collection and its models sync state. Since `$status` updates using Backbone event, passing `{silent: true}` will prevent `$status` from updating. `$status` contains four properties, including:
      - `deleting`: Set to true when one of its models is getting destroyed (HTTP `DELETE` request)
      - `loading`:  Set to true when fetching collection data from server (HTTP `GET` request)
      - `saving`:   Set to true when creating or updating one of its models (HTTP `POST` or `PUT` request)
      - `syncing`:  Set to true whenever a collection has started a request to the server

      HTML:
      ```html
      <ul>
        <li ng-if="users.$status.loading">Loading...</li>
        <li ng-repeat="user in users.$models">{{user.username}}<li>
      </ul>
      ```

      Javascript:
      ```
      $scope.users = new Users();
      $scope.users.fetch();
      ```

    */
    factory('NgBackboneCollection', ['Backbone', 'NgBackboneModel', function(Backbone, NgBackboneModel) {
      return Backbone.Collection.extend({
        model: NgBackboneModel,
        getQueryString: function() {
          // todo: figure out how to call this
          return Backbone.buildQueryString(this.model.prototype.fields, this.model.prototype.objectType);
        },
        constructor: function NgBackboneCollection() {
          var self = this;

          // Initialize status object
          this.$status = {
            deleting: false,
            loading:  false,
            saving:   false,
            syncing:  false
          };

          this.on('request', function(model, xhr, options) {
            this.$setStatus({
              deleting: (options.method === 'DELETE'),
              loading:  (options.method === 'GET'),
              saving:   (options.method === 'POST' || options.method === 'PUT'),
              syncing:  true
            });
          });

          this.on('sync error', this.$resetStatus);

          // For clearing status when destroy model on collection
          this.on('destroy', this.$resetStatus);

          Object.defineProperty(this, '$models', {
            enumerable: true,
            get: function() {
              return self.models;
            }
          });

          Backbone.Collection.apply(this, arguments);
        },

        /*
          @chalk
          @name $setStatus
          @function
          @description
          Update collection status

          @param {Object} attributes Set on or multiple statuses
          @param {Object} options    Options
        */
        $setStatus: function(key, value, options) {
          var attr, attrs;

          if (_.isUndefined(key)) {
            return this;
          }

          if (_.isObject(key)) {
            attrs = key;
            options = value;
          } else {
            (attrs = {})[key] = value;
          }

          options = options || {};

          for (attr in this.$status) {
            if (attrs.hasOwnProperty(attr) && _.isBoolean(attrs[attr])) {
              this.$status[attr] = attrs[attr];
            }
          }
        },

        /*
          @chalk
          @name $resetStatus
          @function
          @description
          Reset all statuses including `deleting`, `loading`, `saving`, and `syncing` back to false
        */
        $resetStatus: function() {
          return this.$setStatus({
            deleting: false,
            loading:  false,
            saving:   false,
            syncing:  false
          });
        }
      });
    }]);

})(window, document);