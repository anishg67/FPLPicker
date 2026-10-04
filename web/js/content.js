// Survey content and the jargon buster, ported from Sources/Views/SurveyView.swift
// and Sources/Models/Glossary.swift.

/** Team status first, then four knowledge questions, then how much control. */
export const QUESTIONS = [
  {
    kind: 'teamStatus',
    prompt: 'Do you already have a fantasy football team?',
    subtitle: "If you do, I'll work from your real squad — your players, your bank, your free transfers — and suggest changes. If not, I'll build you one from nothing.",
    options: [
      { text: "No, I'm starting from scratch", detail: 'Build me a whole squad', score: 0 },
      { text: 'Yes — import it with my team ID', detail: "I'll pull your squad, bank and squad value straight from the game", score: 0 },
      { text: "Yes — I'll enter my 15 players by hand", detail: 'Pick your players, then tell me your bank and free transfers', score: 0 },
    ],
  },
  {
    kind: 'knowledge',
    prompt: 'How much football do you actually watch?',
    subtitle: 'No wrong answer — this just sets how much I explain.',
    options: [
      { text: 'Basically none', detail: 'I know the sport exists', score: 0 },
      { text: 'The odd big game', detail: 'Derbies, finals, highlights', score: 1 },
      { text: 'Most weekends', detail: 'I follow a club', score: 2 },
      { text: 'All of it', detail: 'Match of the Day is appointment TV', score: 3 },
    ],
  },
  {
    kind: 'knowledge',
    prompt: 'How long have you been playing fantasy football?',
    subtitle: 'The game where you pick 15 players under a £100m budget.',
    options: [
      { text: 'This is my first time', detail: null, score: 0 },
      { text: 'A season or two', detail: 'I forget to set my team', score: 1 },
      { text: 'Several seasons', detail: 'I check price changes', score: 2 },
      { text: 'Every season, chasing rank', detail: 'Mini-league is war', score: 3 },
    ],
  },
  {
    kind: 'knowledge',
    prompt: 'How much of the fantasy stats language do you already speak?',
    subtitle: 'Pick the line that sounds familiar. Every term is explained below, and you can read the full list any time.',
    showsGlossary: true,
    options: [
      { text: 'None of it', detail: 'The jargon loses me — explain things as you go', score: 0 },
      { text: 'Clean sheets and bonus points', detail: 'Clean sheet: your team concedes nothing all match. Bonus: 1–3 extra points the game hands to the best performers.', score: 1 },
      { text: 'Those, plus xG and xA', detail: "xG (expected goals) and xA (expected assists) measure how good a player's chances were, whether or not they were scored.", score: 2 },
      { text: 'All of it — FDR, EO, price changes', detail: 'FDR: fixture difficulty, 1 easy to 5 hard. EO: effective ownership, how exposed you are to a player. Prices move as managers buy and sell.', score: 3 },
    ],
  },
  {
    kind: 'knowledge',
    prompt: 'Could you name who takes penalties for most clubs?',
    subtitle: 'Set-piece duty is where a lot of fantasy points hide.',
    options: [
      { text: 'Not a chance', detail: null, score: 0 },
      { text: 'A couple of the big ones', detail: null, score: 1 },
      { text: 'Most of them', detail: null, score: 2 },
      { text: 'Penalties, free kicks and corners', detail: null, score: 3 },
    ],
  },
  {
    kind: 'control',
    prompt: 'How much do you want to decide yourself?',
    subtitle: 'You can change this later at any point.',
    options: [
      { text: 'Nothing — just hand me a team', detail: "I'll trust the numbers", score: 0 },
      { text: 'Budget and my favourite clubs', detail: 'The rest is on you', score: 1 },
      { text: 'Everything', detail: 'Risk, fixtures, must-haves, blocklist', score: 2 },
    ],
  },
];

export function evaluateSurvey(answers) {
  let raw = 0;
  let maximum = 0;
  QUESTIONS.forEach((question, index) => {
    if (question.kind !== 'knowledge') return;
    if (index >= answers.length) return;
    raw += question.options[answers[index]].score;
    maximum += 3;
  });
  const knowledge = maximum > 0 ? Math.round((raw / maximum) * 100) : 0;

  const controlIndex = QUESTIONS.findIndex((question) => question.kind === 'control');
  const control = controlIndex < answers.length ? answers[controlIndex] : 1;
  let recommended;
  if (control === 0) recommended = 'auto';
  else if (control === 1) recommended = 'guided';
  // Someone who knows the game well but asked for full auto still gets full
  // auto — intent wins. The reverse gets a gentle downgrade here.
  else recommended = knowledge < 30 ? 'guided' : 'expert';

  const statusIndex = QUESTIONS.findIndex((question) => question.kind === 'teamStatus');
  const statusAnswer = statusIndex < answers.length ? answers[statusIndex] : 0;
  const teamStatus = ['none', 'importByID', 'manual'][Math.min(statusAnswer, 2)];

  return { knowledge, recommended, teamStatus };
}

export function knowledgeLabel(knowledge) {
  if (knowledge < 30) return 'New to this';
  if (knowledge < 65) return 'Casual fan';
  return 'Seasoned manager';
}

export const TEAM_STATUS_META = {
  none: { title: "I'm starting from scratch", detail: 'Build me a whole squad from nothing' },
  importByID: { title: 'Import it with my team ID', detail: 'Pull my current squad, bank and value straight from the game' },
  manual: { title: "I'll enter my 15 players by hand", detail: 'Pick my players, then tell you my bank and free transfers' },
};

/** Plain-English definitions for the jargon the app (and the community) uses. */
export const GLOSSARY = [
  { term: 'xG', short: 'expected goals', definition: 'How many goals a player would be expected to score from the chances they got. A tap-in is worth close to 1.0 xG, a speculative shot from 30 yards maybe 0.02.', example: 'A striker with 0.6 xG in a match had chances a typical player scores from about 60% of the time — whether or not they actually scored.' },
  { term: 'xA', short: 'expected assists', definition: 'The same idea for passes: how likely the chances a player created were to be scored by a teammate.', example: "A cross that lands on a striker's head six yards out is high xA even if it's headed wide." },
  { term: 'xGI', short: 'expected goal involvements', definition: 'xG and xA added together — a single number for how much attacking threat a player produces.', example: null },
  { term: 'Per 90', short: 'per 90 minutes', definition: 'A stat adjusted to a full match, so substitutes and injured players can be compared fairly with players who start every week.', example: '2 goals in 180 minutes is 1.0 goals per 90.' },
  { term: 'FDR', short: 'fixture difficulty rating', definition: 'The game’s 1-to-5 score for how hard each upcoming match is. 1 and 2 are kind fixtures, 4 and 5 are tough ones. This app averages it over the next few gameweeks.', example: 'A defence averaging 2.1 FDR has an easy run and is more likely to keep clean sheets.' },
  { term: 'Clean sheet', short: null, definition: "Conceding no goals. Goalkeepers and defenders get 4 points for one, midfielders get 1, and it's worth nothing if the player was on for under 60 minutes.", example: null },
  { term: 'Bonus and BPS', short: 'bonus points system', definition: 'After every match the three best performers get 3, 2 and 1 extra points, decided by a behind-the-scenes score called BPS that rewards goals, assists, tackles, saves and passes.', example: null },
  { term: 'Ownership', short: 'selected by percent', definition: 'The share of all managers who own a player. High ownership means everyone has them, so they protect your rank rather than improve it.', example: 'A 70%-owned striker who blanks costs you nothing relative to the field. Missing him when he hauls is what hurts.' },
  { term: 'EO', short: 'effective ownership', definition: 'Ownership adjusted for captaincy — a player owned by 50% and captained by 40% has an effective ownership of about 90%, because captains score double.', example: null },
  { term: 'Differential', short: null, definition: "A player almost nobody owns. If they return, you gain ground on everyone who doesn't have them. If they don't, you lose very little.", example: 'Under about 5% ownership is usually considered a differential.' },
  { term: 'Template', short: null, definition: "The squad most top managers converge on. Owning it keeps you moving with the crowd instead of against it — safe, but it won't win you a mini-league on its own.", example: null },
  { term: 'Free transfer', short: null, definition: 'A swap you can make without penalty. You get one each gameweek and can save them up — this app assumes the current rules, where up to five can be banked.', example: null },
  { term: 'Hit', short: 'points hit', definition: 'Every transfer beyond your free ones costs 4 points. Only worth taking if you expect the new player to beat the old one by more than that.', example: 'A −4 hit that gains you 6 points is a net 2-point win.' },
  { term: 'Chips', short: 'the four one-off boosts', definition: 'Four boosts you can play once each per half-season: Bench Boost, Triple Captain, Free Hit and Wildcard. One set expires at gameweek 19 and a fresh set arrives at gameweek 20.', example: 'Using a chip in a quiet week wastes it — most of their value comes from double and blank gameweeks.' },
  { term: 'Bench Boost', short: null, definition: 'For one gameweek your four substitutes score too, so all 15 count. Worth most when every player has a fixture, ideally two.', example: null },
  { term: 'Triple Captain', short: null, definition: 'For one gameweek your captain scores triple rather than double. Best saved for a premium attacker with two fixtures or one very kind one.', example: null },
  { term: 'Free Hit', short: null, definition: 'Unlimited transfers for a single gameweek, after which your squad snaps back to what it was. The usual use is a blank gameweek, when half your team isn’t playing.', example: null },
  { term: 'Wildcard', short: null, definition: 'Unlimited transfers that you keep, with no points hits. For rebuilding a squad that has drifted away from the players you actually want.', example: null },
  { term: 'Bank', short: 'in the bank', definition: "Money you haven't spent. It sits unused but gives you room to upgrade later.", example: null },
  { term: 'Price change', short: null, definition: 'Player prices drift up or down by £0.1m based on how many managers are buying or selling them. Buying early is how squad value grows.', example: null },
  { term: 'Nailed', short: null, definition: 'A player certain to start every week. The opposite is rotation risk — someone the manager rests or benches unpredictably.', example: null },
  { term: 'Double and blank gameweeks', short: null, definition: "Fixture rescheduling means some clubs play twice in a gameweek (a double) and some don't play at all (a blank). Doubles are worth loading up on.", example: null },
];

export function searchGlossary(query) {
  const trimmed = query.trim().toLowerCase();
  if (!trimmed) return GLOSSARY;
  return GLOSSARY.filter((item) => (
    item.term.toLowerCase().includes(trimmed)
    || (item.short || '').toLowerCase().includes(trimmed)
    || item.definition.toLowerCase().includes(trimmed)
  ));
}
