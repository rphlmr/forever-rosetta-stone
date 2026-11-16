"""Active community translation sources on GitHub and CurseForge."""
from datasources.classic_ua import loader as classic_ua
from datasources.czech_forever import loader as czech_forever
from datasources.polish_forever import loader as polish_forever
from datasources.wowita_quests import loader as wowita_quests
from datasources.wow_forever_it import loader as wow_forever_it
from datasources.wow_forver_italiano import loader as wow_forver_italiano
from datasources.wow_lang import loader as wow_lang
from datasources.questtranslator_tr import loader as questtranslator_tr
from datasources.forever_translated_polish import loader as forever_translated_polish
from datasources.varlden_av_krigskraft import loader as varlden_av_krigskraft
from datasources.forever_tr import loader as forever_tr

SOURCES = {'classic-ua': classic_ua, 'czech-forever': czech_forever, 'polish-forever': polish_forever,
           'wowita-quests': wowita_quests, 'wow-forever-it': wow_forever_it,
           'wow-forver-italiano': wow_forver_italiano, 'wow-lang': wow_lang,
           'questtranslator-tr': questtranslator_tr,
           'forever-translated-polish': forever_translated_polish,
           'varlden-av-krigskraft': varlden_av_krigskraft, 'forever-tr': forever_tr}
