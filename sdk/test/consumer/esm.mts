import { Pythilo, type RuntimeResult, type StartOperation } from 'pythilo';
import { makeClient } from './commonjs.cjs';
const fromCommonJS: Pythilo = makeClient();
const fromESM: ReturnType<typeof makeClient> = new Pythilo({ relay: 'http://127.0.0.1:3212' });
const operation: StartOperation = 'test';
export const where = (result: RuntimeResult) => [result.ranOn.kind, result.ranOn.name, result.ranOn.runtime, result.status, result.exitCode, operation] as const;
fromCommonJS.close();
fromESM.close();
