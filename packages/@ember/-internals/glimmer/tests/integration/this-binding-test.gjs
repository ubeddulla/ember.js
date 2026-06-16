import { set } from '@ember/object';
import { RenderingTestCase, moduleFor, runTask } from 'internal-test-helpers';
import { fn } from '@ember/helper';
import { helperCapabilities, setHelperManager } from '@glimmer/manager';
import { Component } from '../utils/helpers';

moduleFor(
  'Automatic this-binding for class methods directly called from the template',
  class extends RenderingTestCase {
    ['@test class method'](assert) {
      let instance;
      let seenThis;

      class Demo extends Component {
        constructor(...args) {
          super(...args);
          instance = this;
        }

        foo() {
          seenThis = this;
        }

        <template>{{(this.foo)}}</template>
      }

      this.render(`<this.Demo />`, { Demo });

      assert.ok(instance);
      assert.strictEqual(seenThis, instance);
    }

    ['@test maintains binding through property chain'](assert) {
      let innerInstance;
      let seenThis;

      class Inner {
        constructor() {
          innerInstance = this;
        }

        method() {
          seenThis = this;
        }
      }

      class Demo extends Component {
        constructor(...args) {
          super(...args);
          this.obj = new Inner();
        }

        <template>{{ (this.obj.method) }}</template>
      }

      this.render(`<this.Demo />`, { Demo });

      assert.ok(innerInstance);
      assert.strictEqual(seenThis, innerInstance);
    }

    ['@test replacing the base object uses correct `this`'](assert) {
      let instance;
      let seenThis;

      class Inner {
        method() {
          seenThis = this;
        }
      }

      class Demo extends Component {
        constructor(...args) {
          super(...args);
          instance = this;
          this.obj = new Inner();
        }

        <template>{{ (this.obj.method) }}</template>
      }

      this.render(`<this.Demo />`, { Demo });

      let first = instance.obj;
      assert.strictEqual(seenThis, first);

      let second = new Inner();
      runTask(() => set(instance, 'obj', second));

      assert.strictEqual(seenThis, second);
    }

    ['@test a method passed as an argument stays bound to its original object'](assert) {
      let instance;
      let seenThis;

      class Child extends Component {
        <template>{{ (@cb) }}</template>
      }

      class Demo extends Component {
        constructor(...args) {
          super(...args);
          instance = this;
        }

        foo() {
          seenThis = this;
        }

        <template><Child @cb={{this.foo}} /></template>
      }

      this.render(`<this.Demo />`, { Demo });

      assert.strictEqual(seenThis, instance);
    }

    ['@test #let block param preserves this binding on method access'](assert) {
      let innerInstance;
      let seenThis;
      let receivedArg;

      class Inner {
        constructor() {
          innerInstance = this;
        }

        method(arg) {
          seenThis = this;
          receivedArg = arg;
        }
      }

      class Demo extends Component {
        constructor(...args) {
          super(...args);
          this.obj = new Inner();
        }

        <template>
          {{#let this.obj as |o|}}
            {{(o.method "did it")}}
          {{/let}}
        </template>
      }

      this.render(`<this.Demo />`, { Demo });

      assert.ok(innerInstance);
      assert.strictEqual(seenThis, innerInstance);
      assert.strictEqual(receivedArg, 'did it', 'argument is passed through to the method');
    }

    ['@test each over array of objects preserves this binding on item methods'](assert) {
      let seenPairs = [];

      class Item {
        constructor(name) {
          this.name = name;
        }

        greet() {
          seenPairs.push({ self: this, name: this.name });
        }
      }

      let items = [new Item('alice'), new Item('bob'), new Item('carol')];

      class Demo extends Component {
        constructor(...args) {
          super(...args);
          this.items = items;
        }

        <template>
          <ul>
            {{#each this.items as |item|}}
              <li>{{item.greet}}: {{item.name}}</li>
            {{/each}}
          </ul>
        </template>
      }

      this.render(`<this.Demo />`, { Demo });

      assert.strictEqual(seenPairs.length, 3);
      assert.strictEqual(seenPairs[0].self, items[0], 'alice: this is the Item instance');
      assert.strictEqual(seenPairs[0].name, 'alice', 'alice: this.name is correct');
      assert.strictEqual(seenPairs[1].self, items[1], 'bob: this is the Item instance');
      assert.strictEqual(seenPairs[1].name, 'bob', 'bob: this.name is correct');
      assert.strictEqual(seenPairs[2].self, items[2], 'carol: this is the Item instance');
      assert.strictEqual(seenPairs[2].name, 'carol', 'carol: this.name is correct');
    }

    ['@test already-bound functions are unaffected'](assert) {
      let instance;
      let seenThis;

      class Demo extends Component {
        constructor(...args) {
          super(...args);
          instance = this;
        }

        foo = () => {
          seenThis = this;
        };

        <template>{{this.foo}}</template>
      }

      this.render(`<this.Demo />`, { Demo });

      assert.strictEqual(seenThis, instance);
    }

    ['@test (fn) on methods still behaves appropriately'](assert) {
      let instance;
      let seenThis;

      class Demo extends Component {
        constructor(...args) {
          super(...args);
          instance = this;
        }

        foo = () => {
          seenThis = this;
        };

        <template>
          {{#let (fn this.foo) as |fned|}}
            {{ (fned) }}
          {{/let}}
        </template>
      }

      this.render(`<this.Demo />`, { Demo });

      assert.strictEqual(seenThis, instance);
    }

    ['@test a function with a custom helper manager read off a path keeps its manager'](assert) {
      let sawDefinition;

      class MyHelperManager {
        capabilities = helperCapabilities('3.23', { hasValue: true });

        createHelper(definition, args) {
          return { definition, args };
        }

        getValue({ definition }) {
          sawDefinition = definition;
          return 'CUSTOM_MANAGER_RAN';
        }

        getDebugName() {
          return 'my-custom-helper';
        }
      }

      function customHelper() {
        return 'PLAIN_FN_RAN';
      }
      setHelperManager(() => new MyHelperManager(), customHelper);

      class Inner {
        customHelper = customHelper;
      }

      class Demo extends Component {
        constructor(...args) {
          super(...args);
          this.obj = new Inner();
        }

        <template>{{(this.obj.customHelper)}}</template>
      }

      this.render(`<this.Demo />`, { Demo });

      this.assertText('CUSTOM_MANAGER_RAN');
      assert.strictEqual(
        sawDefinition,
        customHelper,
        // i.e.: a.foo !== a.foo.bind(a)
        'the custom manager received the original function, not a `.bind()` wrapper'
      );
    }

    ['@test a plain method passed through (fn) is not this-bound'](assert) {
      let innerInstance;
      let seenThis = 'UNSET';

      class Inner {
        constructor() {
          innerInstance = this;
        }

        method() {
          seenThis = this;
        }
      }

      class Demo extends Component {
        constructor(...args) {
          super(...args);
          this.obj = new Inner();
        }

        <template>{{#let (fn this.obj.method) as |f|}}{{(f)}}{{/let}}</template>
      }

      this.render(`<this.Demo />`, { Demo });

      assert.notStrictEqual(seenThis, 'UNSET', 'the method actually ran');
      assert.notStrictEqual(
        seenThis,
        innerInstance,
        'a plain method passed through `(fn)` is NOT bound to the object it was read from — `(fn)` value-passes the function and only the direct template call site binds'
      );
    }
  }
);
