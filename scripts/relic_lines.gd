class_name RelicLines
extends RefCounted
## Répliques de la relique qui parle : manipulatrice, joueuse, cabotine.

const INTRO := [
	"Oh ! Enfin quelqu'un qui me tient à l'endroit. Bonjour, mon petit hunter.",
	"Oui, je parle. Non, tu n'es pas fou. Enfin... pas à cause de moi.",
	"Il y a d'autres reliques là-dehors. Mes sœurs. Bien moins charmantes que moi, rassure-toi.",
	"Rapporte-les-moi et je te rendrai riche. Ou célèbre. Ou les deux, si tu es sage.",
	"Le terminal, là, vend des implants. Tes pauvres muscles d'origine me font de la peine.",
	"Et la plateforme verte t'emmène au travail. Allez, file. Je t'attends. Je n'ai pas le choix.",
]

## Commentaires sur la dernière run, selon son issue.
const AFTER_RUN := {
	"relic":
	[
		"Une sœur de plus ! Tu vois, quand tu veux. Pose-la près de moi... plus près... voilà.",
		"Elle dit bonjour. Enfin, elle hurle, mais c'est sa façon de dire bonjour.",
		"Tu commences à me plaire, hunter. Ne le prends pas mal, ça ne dure jamais.",
	],
	"loot":
	[
		"Des babioles ? Tu me ramènes des babioles ? Je suis vexée. Pendant au moins dix secondes.",
		"La prochaine fois, ramène la relique. Je ne demande pas grand-chose. Si. Mais gentiment.",
	],
	"dead":
	[
		"Tu es mort. Encore. Heureusement que je suis là pour te recoller... façon de parler.",
		"Ils sont laids, mal coiffés, et pourtant ils t'ont eu. Médite là-dessus.",
		"La mort n'est qu'un léger contretemps. Pour toi. Moi, je m'ennuyais.",
	],
}

## Répliques au hasard, une fois tout le reste dit.
const BANTER := [
	"Tu sais ce qui manque à ce hub ? Un piédestal plus grand. Pour moi. Note-le quelque part.",
	"Le monde est corrompu, les reliques sont à vendre, et toi tu restes planté là. Fascinant.",
	"Je t'ai déjà dit que tu avais une jolie coupe ? Non ? Tant mieux, ç'aurait été un mensonge.",
	"Les autres hunters me cherchaient aussi. Mais je t'ai choisi. Enfin, tu m'as trouvée.",
	"On raconte qu'une relique peut sauver le monde. Moi, par exemple. Peut-être. Si on me flatte.",
	"Un implant de plus et tu seras presque à ma hauteur. Presque.",
]
