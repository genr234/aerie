<script lang="ts">
  import { Plus, Trash2 } from "@lucide/svelte";
  import { combatDecl, vfs } from "../lib/stores";
  import { mutateCombat } from "../lib/actions";
  import { parseCombat } from "../lib/project";

  $: combatPath = $combatDecl?.path;
  $: combat = combatPath ? parseCombat($vfs, combatPath).combat : undefined;
  $: actors = combat?.actors ?? [];
  $: skills = combat?.skills ?? [];
  $: encounters = combat?.encounters ?? [];

  const combatDeclExample = '"combat": { "path": "assets/combat/combat.json" }';

  function toggleValue(values: string[] | undefined, id: string): string[] {
    const current = values ?? [];
    return current.includes(id) ? current.filter((value) => value !== id) : [...current, id];
  }

  function addActor() {
    mutateCombat((doc) => doc.actors.push({
      id: unique("actor", doc.actors.map((a) => a.id)),
      name: "Actor",
      side: "enemy",
      level: 1,
      hp: 12,
      mp: 0,
      attack: 4,
      defense: 1,
      speed: 5,
      skills: [],
    }));
  }

  function addSkill() {
    mutateCombat((doc) => doc.skills.push({
      id: unique("skill", doc.skills.map((s) => s.id)),
      name: "Skill",
      kind: "damage",
      power: 3,
      mpCost: 0,
      target: "enemy",
    }));
  }

  function addEncounter() {
    mutateCombat((doc) => doc.encounters.push({
      id: unique("encounter", doc.encounters.map((e) => e.id)),
      party: doc.actors.filter((a) => a.side === "party").slice(0, 1).map((a) => a.id),
      enemies: doc.actors.filter((a) => a.side === "enemy").slice(0, 1).map((a) => a.id),
      rewards: { xp: 5, gold: 0 },
    }));
  }

  function unique(base: string, existing: string[]): string {
    let i = 1;
    let candidate = base;
    while (existing.includes(candidate)) candidate = `${base}_${++i}`;
    return candidate;
  }

  function renameActor(index: number, nextId: string) {
    mutateCombat((doc) => {
      const previousId = doc.actors[index]?.id;
      if (!previousId) return;
      doc.actors[index].id = nextId;
      for (const encounter of doc.encounters) {
        encounter.party = encounter.party.map((id) => id === previousId ? nextId : id);
        encounter.enemies = encounter.enemies.map((id) => id === previousId ? nextId : id);
      }
    });
  }

  function deleteActor(index: number) {
    mutateCombat((doc) => {
      const actorId = doc.actors[index]?.id;
      doc.actors.splice(index, 1);
      if (!actorId) return;
      for (const encounter of doc.encounters) {
        encounter.party = encounter.party.filter((id) => id !== actorId);
        encounter.enemies = encounter.enemies.filter((id) => id !== actorId);
      }
    });
  }

  function renameSkill(index: number, nextId: string) {
    mutateCombat((doc) => {
      const previousId = doc.skills[index]?.id;
      if (!previousId) return;
      doc.skills[index].id = nextId;
      for (const actor of doc.actors) {
        actor.skills = (actor.skills ?? []).map((id) => id === previousId ? nextId : id);
      }
    });
  }

  function deleteSkill(index: number) {
    mutateCombat((doc) => {
      const skillId = doc.skills[index]?.id;
      doc.skills.splice(index, 1);
      if (!skillId) return;
      for (const actor of doc.actors) {
        actor.skills = (actor.skills ?? []).filter((id) => id !== skillId);
      }
    });
  }
</script>

<div class="combat-workbench">
  {#if !combatPath}
    <div class="empty-state">
      <h2>No combat file</h2>
      <p>Add <code>{combatDeclExample}</code> to game.json.</p>
    </div>
  {:else if !combat}
    <div class="empty-state">
      <h2>Combat file has errors</h2>
      <p>Open the raw editor for {combatPath} to repair the JSON.</p>
    </div>
  {:else}
    <section class="combat-section">
      <header><h2>Actors</h2><button class="tool-button" on:click={addActor}><Plus size={14} />Actor</button></header>
      <div class="combat-grid actors-grid">
        {#each actors as actor, i}
          <article class="combat-card">
            <button class="icon-button danger mini" title="Delete actor" on:click={() => deleteActor(i)}><Trash2 size={14} /></button>
            <label>ID <input value={actor.id} on:change={(e) => renameActor(i, e.currentTarget.value)} /></label>
            <label>Name <input value={actor.name} on:change={(e) => mutateCombat((doc) => doc.actors[i].name = e.currentTarget.value)} /></label>
            <label>Side <select value={actor.side} on:change={(e) => mutateCombat((doc) => doc.actors[i].side = e.currentTarget.value as any)}><option value="party">Party</option><option value="enemy">Enemy</option></select></label>
            <label>Level <input type="number" value={actor.level ?? 1} on:change={(e) => mutateCombat((doc) => doc.actors[i].level = Number(e.currentTarget.value))} /></label>
            <label>HP <input type="number" value={actor.hp} on:change={(e) => mutateCombat((doc) => doc.actors[i].hp = Number(e.currentTarget.value))} /></label>
            <label>MP <input type="number" value={actor.mp ?? 0} on:change={(e) => mutateCombat((doc) => doc.actors[i].mp = Number(e.currentTarget.value))} /></label>
            <label>ATK <input type="number" value={actor.attack} on:change={(e) => mutateCombat((doc) => doc.actors[i].attack = Number(e.currentTarget.value))} /></label>
            <label>DEF <input type="number" value={actor.defense} on:change={(e) => mutateCombat((doc) => doc.actors[i].defense = Number(e.currentTarget.value))} /></label>
            <label>SPD <input type="number" value={actor.speed} on:change={(e) => mutateCombat((doc) => doc.actors[i].speed = Number(e.currentTarget.value))} /></label>
            <div class="combat-picker full-span">
              <span>Skills</span>
              <div class="chip-list">
                {#each skills as skill}
                  <button
                    type="button"
                    class:active={(actor.skills ?? []).includes(skill.id)}
                    on:click={() => mutateCombat((doc) => doc.actors[i].skills = toggleValue(doc.actors[i].skills, skill.id))}
                  >
                    {skill.name || skill.id}
                  </button>
                {/each}
                {#if skills.length === 0}<em>No skills yet</em>{/if}
              </div>
            </div>
          </article>
        {/each}
      </div>
    </section>

    <section class="combat-section">
      <header><h2>Skills</h2><button class="tool-button" on:click={addSkill}><Plus size={14} />Skill</button></header>
      <div class="combat-grid skills-grid">
        {#each skills as skill, i}
          <article class="combat-card">
            <button class="icon-button danger mini" title="Delete skill" on:click={() => deleteSkill(i)}><Trash2 size={14} /></button>
            <label>ID <input value={skill.id} on:change={(e) => renameSkill(i, e.currentTarget.value)} /></label>
            <label>Name <input value={skill.name} on:change={(e) => mutateCombat((doc) => doc.skills[i].name = e.currentTarget.value)} /></label>
            <label>Kind <select value={skill.kind ?? "damage"} on:change={(e) => mutateCombat((doc) => doc.skills[i].kind = e.currentTarget.value as any)}><option value="damage">Damage</option><option value="heal">Heal</option></select></label>
            <label>Target <select value={skill.target ?? "enemy"} on:change={(e) => mutateCombat((doc) => doc.skills[i].target = e.currentTarget.value as any)}><option value="enemy">Enemy</option><option value="ally">Ally</option><option value="self">Self</option></select></label>
            <label>Power <input type="number" value={skill.power ?? 0} on:change={(e) => mutateCombat((doc) => doc.skills[i].power = Number(e.currentTarget.value))} /></label>
            <label>MP Cost <input type="number" value={skill.mpCost ?? 0} on:change={(e) => mutateCombat((doc) => doc.skills[i].mpCost = Number(e.currentTarget.value))} /></label>
          </article>
        {/each}
      </div>
    </section>

    <section class="combat-section">
      <header><h2>Encounters</h2><button class="tool-button" on:click={addEncounter}><Plus size={14} />Encounter</button></header>
      <div class="combat-grid encounters-grid">
        {#each encounters as encounter, i}
          <article class="combat-card">
            <button class="icon-button danger mini" title="Delete encounter" on:click={() => mutateCombat((doc) => doc.encounters.splice(i, 1))}><Trash2 size={14} /></button>
            <label>ID <input value={encounter.id} on:change={(e) => mutateCombat((doc) => doc.encounters[i].id = e.currentTarget.value)} /></label>
            <div class="combat-picker full-span">
              <span>Party</span>
              <div class="chip-list">
                {#each actors.filter((actor) => actor.side === "party") as actor}
                  <button
                    type="button"
                    class:active={encounter.party.includes(actor.id)}
                    on:click={() => mutateCombat((doc) => doc.encounters[i].party = toggleValue(doc.encounters[i].party, actor.id))}
                  >
                    {actor.name || actor.id}
                  </button>
                {/each}
                {#if actors.filter((actor) => actor.side === "party").length === 0}<em>No party actors</em>{/if}
              </div>
            </div>
            <div class="combat-picker full-span">
              <span>Enemies</span>
              <div class="chip-list">
                {#each actors.filter((actor) => actor.side === "enemy") as actor}
                  <button
                    type="button"
                    class:active={encounter.enemies.includes(actor.id)}
                    on:click={() => mutateCombat((doc) => doc.encounters[i].enemies = toggleValue(doc.encounters[i].enemies, actor.id))}
                  >
                    {actor.name || actor.id}
                  </button>
                {/each}
                {#if actors.filter((actor) => actor.side === "enemy").length === 0}<em>No enemy actors</em>{/if}
              </div>
            </div>
            <label>XP <input type="number" value={encounter.rewards?.xp ?? 0} on:change={(e) => mutateCombat((doc) => { doc.encounters[i].rewards ??= {}; doc.encounters[i].rewards!.xp = Number(e.currentTarget.value); })} /></label>
            <label>Gold <input type="number" value={encounter.rewards?.gold ?? 0} on:change={(e) => mutateCombat((doc) => { doc.encounters[i].rewards ??= {}; doc.encounters[i].rewards!.gold = Number(e.currentTarget.value); })} /></label>
            <label>Win Scene <input value={encounter.onWinScene ?? ""} on:change={(e) => mutateCombat((doc) => doc.encounters[i].onWinScene = e.currentTarget.value || undefined)} /></label>
            <label>Lose Scene <input value={encounter.onLoseScene ?? ""} on:change={(e) => mutateCombat((doc) => doc.encounters[i].onLoseScene = e.currentTarget.value || undefined)} /></label>
          </article>
        {/each}
      </div>
    </section>
  {/if}
</div>
