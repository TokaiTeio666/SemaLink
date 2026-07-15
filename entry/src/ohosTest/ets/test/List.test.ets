import abilityTest from './Ability.test';
import collaborationAbilityTest from './CollaborationAbility.test';
import indexPageTest from './IndexPage.test';

export default function testsuite() {
  abilityTest();
  collaborationAbilityTest();
  indexPageTest();
}
